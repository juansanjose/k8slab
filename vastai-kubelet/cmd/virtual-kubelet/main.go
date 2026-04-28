package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/juansanjose/vastai-kubelet/pkg/config"
	"github.com/juansanjose/vastai-kubelet/pkg/vastai"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/fields"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/cache"
	"k8s.io/klog/v2"
)

const (
	annotationInstanceID = "vast.ai/instance-id"
	annotationGPUName    = "vast.ai/gpu-name"
	annotationMaxDPH     = "vast.ai/max-dph"
	annotationDiskGB     = "vast.ai/disk-gb"
	labelManagedBy       = "app.kubernetes.io/managed-by"
	labelNodeName        = "vast.ai/node-name"
	labelInstances       = "vast.ai/instances"
)

type Controller struct {
	clientset kubernetes.Interface
	vastAI    *vastai.Client
	config    *config.Config
	nodeName  string
}

func NewController(cfg *config.Config) (*Controller, error) {
	// In-cluster config
	k8sConfig, err := rest.InClusterConfig()
	if err != nil {
		return nil, fmt.Errorf("failed to get in-cluster config: %w", err)
	}

	clientset, err := kubernetes.NewForConfig(k8sConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to create clientset: %w", err)
	}

	return &Controller{
		clientset: clientset,
		vastAI:    vastai.NewClient(cfg.VastAIKey),
		config:    cfg,
		nodeName:  cfg.NodeName,
	}, nil
}

func (c *Controller) Run(ctx context.Context) error {
	// Create virtual node if it doesn't exist
	if err := c.ensureVirtualNode(ctx); err != nil {
		return fmt.Errorf("failed to ensure virtual node: %w", err)
	}

	// Watch pods scheduled to our virtual node
	watchList := cache.NewListWatchFromClient(
		c.clientset.CoreV1().RESTClient(),
		"pods",
		corev1.NamespaceAll,
		fields.SelectorFromSet(fields.Set{
			"spec.nodeName": c.nodeName,
		}),
	)

	_, informer := cache.NewInformer(
		watchList,
		&corev1.Pod{},
		30*time.Second,
		cache.ResourceEventHandlerFuncs{
			AddFunc:    c.onPodAdd,
			UpdateFunc: c.onPodUpdate,
			DeleteFunc: c.onPodDelete,
		},
	)

	klog.InfoS("Starting Vast.ai controller", "node", c.nodeName)
	go informer.Run(ctx.Done())

	// Start node heartbeat to keep node Ready
	go c.nodeHeartbeat(ctx)

	// Periodic sync of instance status
	ticker := time.NewTicker(c.config.SyncInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
			c.syncInstanceStatus(ctx)
		}
	}
}

func (c *Controller) nodeHeartbeat(ctx context.Context) {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			node, err := c.clientset.CoreV1().Nodes().Get(ctx, c.nodeName, metav1.GetOptions{})
			if err != nil {
				klog.ErrorS(err, "Failed to get node for heartbeat")
				continue
			}

			node.Status.Conditions = []corev1.NodeCondition{
				{
					Type:               corev1.NodeReady,
					Status:             corev1.ConditionTrue,
					LastHeartbeatTime:  metav1.Now(),
					LastTransitionTime: metav1.Now(),
					Reason:             "KubeletReady",
					Message:            "Vast.ai virtual kubelet is running",
				},
			}

			_, err = c.clientset.CoreV1().Nodes().UpdateStatus(ctx, node, metav1.UpdateOptions{})
			if err != nil {
				klog.ErrorS(err, "Failed to update node heartbeat")
			}
		}
	}
}

func (c *Controller) ensureVirtualNode(ctx context.Context) error {
	_, err := c.clientset.CoreV1().Nodes().Get(ctx, c.nodeName, metav1.GetOptions{})
	if err == nil {
		return nil // Node exists
	}

	// Create virtual node
	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{
			Name: c.nodeName,
			Labels: map[string]string{
				"kubernetes.io/role":       "agent",
				"kubernetes.io/os":         "linux",
				"kubernetes.io/arch":       "amd64",
				"node.kubernetes.io/instance-type": "vastai-gpu",
			},
			Annotations: map[string]string{
				"node.alpha.kubernetes.io/ttl": "0",
			},
		},
		Spec: corev1.NodeSpec{
			Taints: []corev1.Taint{
				{
					Key:    "virtual-kubelet.io/provider",
					Value:  "vastai",
					Effect: corev1.TaintEffectNoSchedule,
				},
			},
		},
		Status: corev1.NodeStatus{
			Phase: corev1.NodeRunning,
			Conditions: []corev1.NodeCondition{
				{
					Type:   corev1.NodeReady,
					Status: corev1.ConditionTrue,
					Reason: "KubeletReady",
				},
			},
			Capacity: corev1.ResourceList{
				corev1.ResourcePods: resource.MustParse("100"),
			},
			Allocatable: corev1.ResourceList{
				corev1.ResourcePods: resource.MustParse("100"),
			},
			NodeInfo: corev1.NodeSystemInfo{
				OSImage:        "Vast.ai Virtual Node",
				KernelVersion:  "virtual",
				ContainerRuntimeVersion: "docker",
				KubeletVersion: "v1.0.0-vastai",
			},
		},
	}

	_, err = c.clientset.CoreV1().Nodes().Create(ctx, node, metav1.CreateOptions{})
	if err != nil {
		return fmt.Errorf("failed to create virtual node: %w", err)
	}

	klog.InfoS("Created virtual node", "node", c.nodeName)
	return nil
}

func (c *Controller) onPodAdd(obj interface{}) {
	pod := obj.(*corev1.Pod)
	klog.InfoS("Pod added", "pod", pod.Name, "namespace", pod.Namespace)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	if err := c.provisionInstance(ctx, pod); err != nil {
		klog.ErrorS(err, "Failed to provision instance", "pod", pod.Name)
		c.updatePodStatus(ctx, pod, corev1.PodFailed, fmt.Sprintf("Failed to provision: %v", err))
	}
}

func (c *Controller) onPodUpdate(oldObj, newObj interface{}) {
	// Only handle status updates from our sync loop
}

func (c *Controller) onPodDelete(obj interface{}) {
	pod := obj.(*corev1.Pod)
	klog.InfoS("Pod deleted", "pod", pod.Name, "namespace", pod.Namespace)

	instanceID := getInstanceID(pod)
	if instanceID == 0 {
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	if err := c.vastAI.DestroyInstance(instanceID); err != nil {
		klog.ErrorS(err, "Failed to destroy instance", "instance", instanceID)
	} else {
		klog.InfoS("Destroyed instance", "instance", instanceID)
	}

	c.updateNodeInstanceLabel(ctx, instanceID, false)
}

func (c *Controller) provisionInstance(ctx context.Context, pod *corev1.Pod) error {
	// Parse annotations
	gpuName := pod.Annotations[annotationGPUName]
	maxDPH := c.config.MaxDPH
	if v := pod.Annotations[annotationMaxDPH]; v != "" {
		fmt.Sscanf(v, "%f", &maxDPH)
	}

	diskGB := 10.0
	if v := pod.Annotations[annotationDiskGB]; v != "" {
		fmt.Sscanf(v, "%f", &diskGB)
	}

	// Search for cheapest offer
	klog.InfoS("Searching for GPU", "gpu", gpuName, "maxDPH", maxDPH)
	offers, err := c.vastAI.SearchOffers(gpuName, c.config.MinComputeCap, maxDPH, c.config.SearchLimit)
	if err != nil {
		return fmt.Errorf("search failed: %w", err)
	}

	if len(offers) == 0 {
		return fmt.Errorf("no offers found matching criteria")
	}

	// Build env vars
	env := make(map[string]string)
	for _, e := range pod.Spec.Containers[0].Env {
		env[e.Name] = e.Value
	}

	// Build onstart script with network setup
	userCmd := ""
	if len(pod.Spec.Containers[0].Command) > 0 {
		userCmd = buildCommand(pod.Spec.Containers[0].Command, pod.Spec.Containers[0].Args)
	}
	
	// Get cluster IP from env or use default
	clusterIP := os.Getenv("CLUSTER_IP")
	if clusterIP == "" {
		// Try to get from pod env or use a default
		clusterIP = "100.87.186.22"
	}
	
	onStart := buildOnStartScript(pod.Name, pod.Namespace, userCmd, c.config.TailscaleAuthKey, clusterIP)

	// Determine image
	image := pod.Spec.Containers[0].Image
	if image == "" {
		image = c.config.DefaultImage
	}

	// Try each offer until one succeeds
	var instanceID int
	var lastErr error
	for _, offer := range offers {
		klog.InfoS("Trying offer", "id", offer.ID, "gpu", offer.GPUName, "dph", offer.DPHTotal)
		instanceID, lastErr = c.vastAI.CreateInstance(offer.ID, image, env, onStart, diskGB)
		if lastErr == nil {
			klog.InfoS("Created instance", "instance", instanceID, "offer", offer.ID)
			break
		}
		klog.ErrorS(lastErr, "Offer failed, trying next", "offer", offer.ID)
	}

	if lastErr != nil {
		return fmt.Errorf("all offers failed, last error: %w", lastErr)
	}

	// Re-fetch pod to get latest version
	freshPod, err := c.clientset.CoreV1().Pods(pod.Namespace).Get(ctx, pod.Name, metav1.GetOptions{})
	if err != nil {
		c.vastAI.DestroyInstance(instanceID)
		return fmt.Errorf("failed to get fresh pod: %w", err)
	}

	// Annotate pod with instance ID
	if freshPod.Annotations == nil {
		freshPod.Annotations = make(map[string]string)
	}
	freshPod.Annotations[annotationInstanceID] = fmt.Sprintf("%d", instanceID)
	_, err = c.clientset.CoreV1().Pods(pod.Namespace).Update(ctx, freshPod, metav1.UpdateOptions{})
	if err != nil {
		// Try to destroy instance if annotation fails
		c.vastAI.DestroyInstance(instanceID)
		return fmt.Errorf("failed to annotate pod: %w", err)
	}

	// Update status to Pending
	c.updatePodStatus(ctx, freshPod, corev1.PodPending, "Instance creating")

	// Update node label with instance ID
	c.updateNodeInstanceLabel(ctx, instanceID, true)

	return nil
}

func (c *Controller) updateNodeInstanceLabel(ctx context.Context, instanceID int, add bool) {
	node, err := c.clientset.CoreV1().Nodes().Get(ctx, c.nodeName, metav1.GetOptions{})
	if err != nil {
		klog.ErrorS(err, "Failed to get node for label update")
		return
	}

	if node.Labels == nil {
		node.Labels = make(map[string]string)
	}

	instances := node.Labels[labelInstances]
	instanceStr := fmt.Sprintf("%d", instanceID)

	if add {
		if instances == "" {
			node.Labels[labelInstances] = instanceStr
		} else if !strings.Contains(instances, instanceStr) {
			node.Labels[labelInstances] = instances + "," + instanceStr
		}
	} else {
		if instances == instanceStr {
			delete(node.Labels, labelInstances)
		} else if strings.Contains(instances, instanceStr) {
			parts := strings.Split(instances, ",")
			var newParts []string
			for _, p := range parts {
				if p != instanceStr {
					newParts = append(newParts, p)
				}
			}
			if len(newParts) > 0 {
				node.Labels[labelInstances] = strings.Join(newParts, ",")
			} else {
				delete(node.Labels, labelInstances)
			}
		}
	}

	_, err = c.clientset.CoreV1().Nodes().Update(ctx, node, metav1.UpdateOptions{})
	if err != nil {
		klog.ErrorS(err, "Failed to update node labels")
	} else {
		klog.InfoS("Updated node instance label", "node", c.nodeName, "instances", node.Labels[labelInstances])
	}
}

func (c *Controller) syncInstanceStatus(ctx context.Context) {
	klog.InfoS("Syncing instance status")
	instances, err := c.vastAI.ListInstances()
	if err != nil {
		klog.ErrorS(err, "Failed to list instances")
		return
	}

	// Build instance map
	instanceMap := make(map[int]*vastai.Instance)
	for i := range instances {
		instanceMap[instances[i].ID] = &instances[i]
	}

	// List all pods on our node
	pods, err := c.clientset.CoreV1().Pods(corev1.NamespaceAll).List(ctx, metav1.ListOptions{
		FieldSelector: fmt.Sprintf("spec.nodeName=%s", c.nodeName),
	})
	if err != nil {
		klog.ErrorS(err, "Failed to list pods")
		return
	}

	for _, pod := range pods.Items {
		instanceID := getInstanceID(&pod)
		if instanceID == 0 {
			continue
		}

		instance, ok := instanceMap[instanceID]
		if !ok {
			// Instance not found, mark as failed
			c.updatePodStatus(ctx, &pod, corev1.PodFailed, "Instance not found")
			continue
		}

		// Map Vast.ai status to Pod phase
		var phase corev1.PodPhase
		var message string

		switch instance.Status {
		case "running":
			phase = corev1.PodRunning
			message = fmt.Sprintf("GPU: %s, DPH: $%.2f", instance.GPUName, instance.DPHTotal)
		case "created", "starting", "loading":
			phase = corev1.PodPending
			message = fmt.Sprintf("Instance %s...", instance.Status)
		case "offline", "unloaded":
			phase = corev1.PodFailed
			message = "Instance offline"
		default:
			phase = corev1.PodUnknown
			message = fmt.Sprintf("Status: %s", instance.Status)
		}

		c.updatePodStatus(ctx, &pod, phase, message)
	}
}

func (c *Controller) updatePodStatus(ctx context.Context, pod *corev1.Pod, phase corev1.PodPhase, message string) {
	// Re-fetch pod to get latest version
	freshPod, err := c.clientset.CoreV1().Pods(pod.Namespace).Get(ctx, pod.Name, metav1.GetOptions{})
	if err != nil {
		klog.ErrorS(err, "Failed to get fresh pod for status update", "pod", pod.Name)
		return
	}

	freshPod.Status.Phase = phase
	freshPod.Status.Message = message

	now := metav1.Now()
	freshPod.Status.Conditions = []corev1.PodCondition{
		{
			Type:    corev1.PodReady,
			Status:  corev1.ConditionFalse,
			Reason:  string(phase),
			Message: message,
			LastTransitionTime: now,
		},
	}

	if phase == corev1.PodRunning {
		freshPod.Status.Conditions[0].Status = corev1.ConditionTrue
	}

	_, err = c.clientset.CoreV1().Pods(pod.Namespace).UpdateStatus(ctx, freshPod, metav1.UpdateOptions{})
	if err != nil {
		klog.ErrorS(err, "Failed to update pod status", "pod", pod.Name)
	}
}

func getInstanceID(pod *corev1.Pod) int {
	if pod.Annotations == nil {
		return 0
	}
	var id int
	fmt.Sscanf(pod.Annotations[annotationInstanceID], "%d", &id)
	return id
}

func buildCommand(cmd, args []string) string {
	if len(cmd) == 0 {
		return ""
	}
	result := cmd[0]
	if len(cmd) > 1 {
		result += " " + strings.Join(cmd[1:], " ")
	}
	if len(args) > 0 {
		result += " " + strings.Join(args, " ")
	}
	return result
}

func buildOnStartScript(podName, namespace, userCmd, tailscaleAuthKey, clusterIP string) string {
	script := `#!/bin/bash
set -e

echo "=== Vast.ai GPU Container ==="
echo "Pod: ` + podName + `"
echo "Namespace: ` + namespace + `"
echo ""

# Install Tailscale if not present
if ! command -v tailscale &> /dev/null; then
    echo "[1/4] Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
fi

# Start Tailscale
echo "[2/4] Starting Tailscale..."
tailscaled --tun=userspace-networking --socks5-server=localhost:1080 --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock > /var/log/tailscaled.log 2>&1 &
sleep 3

# Authenticate
echo "[3/4] Authenticating with Tailscale..."
tailscale up --authkey=` + tailscaleAuthKey + ` --accept-routes --netfilter-mode=off

# Wait for IP
TAILSCALE_IP=""
for i in {1..10}; do
  TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || true)
  if [[ -n "$TAILSCALE_IP" ]]; then
    break
  fi
  echo "Waiting for Tailscale IP... ($i/10)"
  sleep 2
done

if [[ -z "$TAILSCALE_IP" ]]; then
    echo "ERROR: Tailscale failed to get IP"
    exit 1
fi

echo "Tailscale IP: $TAILSCALE_IP"
echo ""

# Set proxy for reaching cluster services
export HTTP_PROXY=socks5://localhost:1080
export HTTPS_PROXY=socks5://localhost:1080
export http_proxy=socks5://localhost:1080
export https_proxy=socks5://localhost:1080

# Configure proxychains for tools that don't support SOCKS5 directly
if command -v proxychains4 &> /dev/null; then
    echo "strict_chain" > /etc/proxychains4.conf
    echo "tcp_read_time_out 15000" >> /etc/proxychains4.conf
    echo "tcp_connect_time_out 8000" >> /etc/proxychains4.conf
    echo "" >> /etc/proxychains4.conf
    echo "[ProxyList]" >> /etc/proxychains4.conf
    echo "socks5 127.0.0.1 1080" >> /etc/proxychains4.conf
fi

echo "Cluster services reachable via:"
echo "  k3s API: https://` + clusterIP + `:6443"
echo "  MLflow: http://` + clusterIP + `:30500"
echo "  MinIO: http://` + clusterIP + `:30900"
echo ""

# Test connectivity
echo "[4/4] Testing cluster connectivity..."
if curl -k --max-time 10 -s -o /dev/null https://` + clusterIP + `:6443; then
    echo "Connected to k3s API server"
else
    echo "WARNING: Cannot reach k3s API server (this is OK if not needed)"
fi
echo ""

echo "=== Running Pod Command ==="
echo ""

# Run the actual pod command
` + userCmd + `

EXIT_CODE=$?
echo ""
echo "=== Command exited with code $EXIT_CODE ==="
exit $EXIT_CODE
`
	return script
}

func main() {
	cfg := config.Load()
	
	if cfg.VastAIKey == "" {
		klog.Fatal("VASTAI_API_KEY environment variable is required")
	}

	ctrl, err := NewController(cfg)
	if err != nil {
		klog.Fatalf("Failed to create controller: %v", err)
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	if err := ctrl.Run(ctx); err != nil {
		klog.Fatalf("Controller failed: %v", err)
	}
}