// ============================================================
// operator/api/v1alpha1/groupversion_info.go
// Registers the mlaccel.io/v1alpha1 API group with the scheme.
// ============================================================

// +kubebuilder:object:generate=true
// +groupName=mlaccel.io
package v1alpha1

import (
    "k8s.io/apimachinery/pkg/runtime/schema"
    "sigs.k8s.io/controller-runtime/pkg/scheme"
)

var (
    // GroupVersion is the group and version of this API.
    GroupVersion = schema.GroupVersion{Group: "mlaccel.io", Version: "v1alpha1"}

    // SchemeBuilder collects the scheme registration functions.
    SchemeBuilder = &scheme.Builder{GroupVersion: GroupVersion}

    // AddToScheme adds this group's types to the scheme.
    AddToScheme = SchemeBuilder.AddToScheme
)