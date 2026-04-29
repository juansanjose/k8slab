package vastai

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const baseURL = "https://console.vast.ai/api/v0"

type Client struct {
	apiKey string
	client *http.Client
}

func NewClient(apiKey string) *Client {
	return &Client{
		apiKey: apiKey,
		client: &http.Client{Timeout: 30 * time.Second},
	}
}

// SearchOffer represents a Vast.ai GPU offer
type SearchOffer struct {
	ID          int     `json:"id"`
	GPUName     string  `json:"gpu_name"`
	NumGPUs     int     `json:"num_gpus"`
	DLPerf      float64 `json:"dlperf"`
	DLPerfPerDP float64 `json:"dlperf_per_dphtotal"`
	DPHBase     float64 `json:"dph_base"`
	DPHTotal    float64 `json:"dph_total"`
	InetUp      float64 `json:"inet_up"`
	InetDown    float64 `json:"inet_down"`
	VRAM        float64 `json:"gpu_ram"`
	DiskSpace   float64 `json:"disk_space"`
	MachineID   int     `json:"machine_id"`
	HostID      int     `json:"host_id"`
	CudaMaxGood float64 `json:"cuda_max_good"`
	NumCPUs     int     `json:"cpu_cores"`
	CPUName     string  `json:"cpu_name"`
	Mobo        string  `json:"mobo"`
	PCIe        float64 `json:"pcie_bw"`
}

type searchResponse struct {
	Offers []SearchOffer `json:"offers"`
}

// SearchOffers finds GPU instances matching criteria
func (c *Client) SearchOffers(gpuName string, minCuda int, maxDPH float64, limit int) ([]SearchOffer, error) {
	// Vast.ai search API - use simple endpoint
	reqURL := baseURL + "/bundles/"
	
	// Add basic query params if supported
	q := url.Values{}
	q.Set("q", "{}")
	if limit > 0 {
		reqURL = fmt.Sprintf("%s?%s", reqURL, q.Encode())
	}
	req, err := http.NewRequest("GET", reqURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("search failed: %s - %s", resp.Status, string(body))
	}

	var result searchResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, err
	}

	return result.Offers, nil
}

// CreateInstanceRequest represents instance creation params
type CreateInstanceRequest struct {
	ClientID    string   `json:"client_id"`
	Image       string   `json:"image"`
	Env         []string `json:"env"`
	OnStart     string   `json:"onstart"`
	GPUCount    int      `json:"gpu_count"`
	Disk        float64  `json:"disk"`
	PackageUUID string   `json:"package_uuid,omitempty"`
}

type createResponse struct {
	Success bool `json:"success"`
	Data    struct {
		InstanceID int `json:"instance_id"`
	} `json:"data"`
	NewContract int `json:"new_contract"`
}

// CreateInstance creates a new instance from an offer
func (c *Client) CreateInstance(offerID int, image string, env map[string]string, onStart string, diskGB float64) (int, error) {
	envList := []string{}
	for k, v := range env {
		envList = append(envList, fmt.Sprintf("%s=%s", k, v))
	}

	payload := map[string]interface{}{
		"client_id":     "kubelet",
		"image":         image,
		"env":           envList,
		"onstart":       onStart,
		"disk":          diskGB,
		"image_runtype": "ssh",
		"gpu_count":     1,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return 0, err
	}

	reqURL := fmt.Sprintf("%s/asks/%d/", baseURL, offerID)
	req, err := http.NewRequest("PUT", reqURL, strings.NewReader(string(body)))
	if err != nil {
		return 0, err
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, err
	}

	if resp.StatusCode != http.StatusOK {
		return 0, fmt.Errorf("create failed: %s - %s", resp.Status, string(respBody))
	}

	var result createResponse
	if err := json.Unmarshal(respBody, &result); err != nil {
		return 0, err
	}

	if !result.Success {
		return 0, fmt.Errorf("create failed: %s", string(respBody))
	}

	if result.Data.InstanceID != 0 {
		return result.Data.InstanceID, nil
	}
	if result.NewContract != 0 {
		return result.NewContract, nil
	}

	return 0, fmt.Errorf("create response did not contain instance ID: %s", string(respBody))
}

// Instance represents a running Vast.ai instance
type Instance struct {
	ID          int     `json:"id"`
	GPUName     string  `json:"gpu_name"`
	Status      string  `json:"actual_status"`
	Image       string  `json:"image_uuid"`
	MachineID   int     `json:"machine_id"`
	DPHBase     float64 `json:"dph_base"`
	DPHTotal    float64 `json:"dph_total"`
	InetUp      float64 `json:"inet_up"`
	InetDown    float64 `json:"inet_down"`
	VRAM        float64 `json:"gpu_ram"`
	NumGPUs     int     `json:"num_gpus"`
	CurState    string  `json:"cur_state"`
}

type instancesResponse struct {
	Instances []Instance `json:"instances"`
}

// ListInstances returns all active instances
func (c *Client) ListInstances() ([]Instance, error) {
	req, err := http.NewRequest("GET", baseURL+"/instances/", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("list failed: %s - %s", resp.Status, string(body))
	}

	var result instancesResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, err
	}

	return result.Instances, nil
}

// DestroyInstance terminates an instance
func (c *Client) DestroyInstance(instanceID int) error {
	req, err := http.NewRequest("DELETE", fmt.Sprintf("%s/instances/%d/", baseURL, instanceID), nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("destroy failed: %s - %s", resp.Status, string(body))
	}

	return nil
}