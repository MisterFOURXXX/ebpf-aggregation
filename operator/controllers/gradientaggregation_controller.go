package controllers

import (
	"context"

	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	mlaccelv1alpha1 "github.com/misterfourxxx/ebpf-aggregation/operator/api/v1alpha1"
)

type GradientAggregationReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=mlaccel.io,resources=gradientaggregations,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=mlaccel.io,resources=gradientaggregations/status,verbs=get;update;patch

func (r *GradientAggregationReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	var ga mlaccelv1alpha1.GradientAggregation
	if err := r.Get(ctx, req.NamespacedName, &ga); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	logger.Info("reconciling GradientAggregation",
		"name", ga.Name,
		"workers", ga.Spec.Workers,
		"mode", ga.Spec.AggregationMode)

	// Stub: mark Running. A full implementation would call bpfd here.
	ga.Status.Phase = "Running"
	ga.Status.BPFProgramLoaded = true
	ga.Status.Message = "Stub reconciler - bpfd call not yet implemented"
	if err := r.Status().Update(ctx, &ga); err != nil {
		logger.Error(err, "failed to update status")
		return ctrl.Result{}, err
	}

	return ctrl.Result{}, nil
}

func (r *GradientAggregationReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&mlaccelv1alpha1.GradientAggregation{}).
		Complete(r)
}