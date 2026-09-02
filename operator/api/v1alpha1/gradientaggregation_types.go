package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

type AggregationMode string

const (
	EBPFOnly AggregationMode = "ebpf-only"
	P4Only   AggregationMode = "p4-only"
	Hybrid   AggregationMode = "hybrid"
)

type SmartNICSelector struct {
	Model string `json:"model,omitempty"`
}

type EBPFPolicy struct {
	Priority string `json:"priority,omitempty"`
}

type GradientAggregationSpec struct {
	Workers          int32            `json:"workers,omitempty"`
	AggregationMode  AggregationMode  `json:"aggregationMode,omitempty"`
	SmartNICSelector *SmartNICSelector `json:"smartNICSelector,omitempty"`
	EBPFPolicy       *EBPFPolicy      `json:"eBPFPolicy,omitempty"`
	Metrics          []string         `json:"metrics,omitempty"`
}

type GradientAggregationStatus struct {
	Phase            string `json:"phase,omitempty"`
	BPFProgramLoaded bool   `json:"bpfProgramLoaded,omitempty"`
	P4ProgramLoaded  bool   `json:"p4ProgramLoaded,omitempty"`
	Message          string `json:"message,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=gradientaggregations,scope=Namespaced

type GradientAggregation struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              GradientAggregationSpec   `json:"spec,omitempty"`
	Status            GradientAggregationStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

type GradientAggregationList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []GradientAggregation `json:"items"`
}

func init() {
	SchemeBuilder.Register(&GradientAggregation{}, &GradientAggregationList{})
}