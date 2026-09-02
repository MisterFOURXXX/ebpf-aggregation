module github.com/misterfourxxx/ebpf-aggregation

go 1.21

require (
    k8s.io/apimachinery v0.28.0
    k8s.io/client-go v0.28.0
    sigs.k8s.io/controller-runtime v0.16.0
)

// `go mod tidy` will add indirect dependencies.