package clustermesh

import (
	"github.com/cilium/cilium/pkg/kvstore/store"
	"github.com/cilium/cilium/pkg/lock"
)

type remoteNodeObserver struct {
	remoteCluster *remoteCluster
	swg           *lock.StoppableWaitGroup
}

func (r remoteNodeObserver) OnDelete(k store.NamedKey) {
	panic("implement me")
}

func (r remoteNodeObserver) OnUpdate(k store.Key) {
	panic("implement me")
}
