package ipcache

import (
	"context"

	"k8s.io/apimachinery/pkg/util/wait"

	"github.com/cilium/cilium/pkg/identity"
	"github.com/cilium/cilium/pkg/k8s"
	ciliumv2 "github.com/cilium/cilium/pkg/k8s/apis/cilium.io/v2"
	clientset "github.com/cilium/cilium/pkg/k8s/client/clientset/versioned"
	"github.com/cilium/cilium/pkg/k8s/informer"
	"github.com/cilium/cilium/pkg/k8s/types"

	"net"

	"github.com/cilium/cilium/pkg/node"
	"github.com/cilium/cilium/pkg/policy"
	"github.com/cilium/cilium/pkg/source"
	"github.com/cilium/cilium/pkg/u8proto"
	k8sv1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/fields"
	"k8s.io/client-go/tools/cache"
)

type K8sIPIdentityWatcher struct {
	ctx context.Context

	ciliumClient clientset.Interface
}

func NewK8sIPIdentityWatcher(client clientset.Interface) *K8sIPIdentityWatcher {
	return &K8sIPIdentityWatcher{
		ciliumClient: client,
	}
}

func (k *K8sIPIdentityWatcher) Watch(ctx context.Context) {
	_, ciliumEndpointInformer := informer.NewInformer(
		cache.NewListWatchFromClient(k.ciliumClient.CiliumV2().RESTClient(),
			"ciliumendpoints", k8sv1.NamespaceAll, fields.Everything()),
		&ciliumv2.CiliumEndpoint{},
		0,
		cache.ResourceEventHandlerFuncs{
			AddFunc: k.updateEndpoint,
			UpdateFunc: func(_, newObj interface{}) {
				k.updateEndpoint(newObj)
			},
			DeleteFunc: func(obj interface{}) {
				deletedObj, ok := obj.(cache.DeletedFinalStateUnknown)
				if ok {
					k.deleteEndpoint(deletedObj.Obj)
				} else {
					k.deleteEndpoint(obj)
				}
			},
		},
		k8s.ConvertToCiliumEndpoint,
	)
	go ciliumEndpointInformer.Run(wait.NeverStop)
}

func (k *K8sIPIdentityWatcher) Close() {
}

func (k *K8sIPIdentityWatcher) updateEndpoint(obj interface{}) {
	endpoint, ok := obj.(types.CiliumEndpoint)
	if !ok {
		return
	}
	// default to the standard key
	encryptionKey := node.GetIPsecKeyIdentity()

	id := identity.ReservedIdentityUnmanaged
	if endpoint.Identity != nil {
		id = identity.NumericIdentity(endpoint.Identity.ID)
	}

	if endpoint.Encryption != nil {
		encryptionKey = uint8(endpoint.Encryption.Key)
	}

	if endpoint.Networking != nil {
		if endpoint.Networking.NodeIP == "" {
			return
		}
		nodeIP := net.ParseIP(endpoint.Networking.NodeIP)
		if nodeIP == nil {
			return
		}

		k8sMeta := &K8sMetadata{
			Namespace:  endpoint.Namespace,
			PodName:    endpoint.Namespace,
			NamedPorts: make(policy.NamedPortMap, len(endpoint.NamedPorts)),
		}

		for _, port := range endpoint.NamedPorts {
			p, err := u8proto.ParseProtocol(port.Protocol)
			if err != nil {
				continue
			}
			k8sMeta.NamedPorts[port.Name] = policy.PortProto{
				Port:  uint16(port.Port),
				Proto: uint8(p),
			}
		}

		for _, pair := range endpoint.Networking.Addressing {
			if pair.IPV4 != "" {
				_, _ = IPIdentityCache.Upsert(pair.IPV4, nodeIP, encryptionKey, k8sMeta,
					Identity{ID: id, Source: source.CustomResource})
			}

			if pair.IPV6 != "" {
				_, _ = IPIdentityCache.Upsert(pair.IPV6, nodeIP, encryptionKey, k8sMeta,
					Identity{ID: id, Source: source.CustomResource})
			}

		}
	}
}

func (k *K8sIPIdentityWatcher) deleteEndpoint(obj interface{}) {
	endpoint, ok := obj.(types.CiliumEndpoint)
	if !ok {
		return
	}
	if endpoint.Networking != nil {
		for _, pair := range endpoint.Networking.Addressing {
			if pair.IPV4 != "" {
				_ = IPIdentityCache.Delete(pair.IPV4, source.CustomResource)
			}

			if pair.IPV6 != "" {
				_ = IPIdentityCache.Delete(pair.IPV6, source.CustomResource)
			}
		}
	}
}
