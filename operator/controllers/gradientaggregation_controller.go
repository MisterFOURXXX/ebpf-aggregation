package controllers

import (
	"context"
	"time"

	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	mlaccelv1alpha1 "github.com/your-username/ebpf-p4-agg/operator/api/v1alpha1"
)

type GradientAggregationReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=mlaccel.io,resources=gradientaggregations,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=mlaccel.io,resources=gradientaggregations/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps,resources=daemonsets,verbs=get;list;watch
// +kubebuilder:rbac:groups=core,resources=pods,verbs=get;list;watch

func (r *GradientAggregationReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := log.FromContext(ctx)
	instance := &mlaccelv1alpha1.GradientAggregation{}
	if err := r.Get(ctx, req.NamespacedName, instance); err != nil {
		if errors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	log.Info("Reconciling", "name", instance.Name, "mode", instance.Spec.AggregationMode)

	if instance.Spec.AggregationMode == mlaccelv1alpha1.EBPFOnly ||
		instance.Spec.AggregationMode == mlaccelv1alpha1.Hybrid {
		instance.Status.BPFProgramLoaded = true
		instance.Status.Phase = "Running"
		instance.Status.Message = "eBPF program loaded (simulated)"
	}

	if instance.Spec.AggregationMode == mlaccelv1alpha1.P4Only ||
		instance.Spec.AggregationMode == mlaccelv1alpha1.Hybrid {
		instance.Status.P4ProgramLoaded = true
	}

	if err := r.Status().Update(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}

	return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
}

func (r *GradientAggregationReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&mlaccelv1alpha1.GradientAggregation{}).
		Complete(r)
}