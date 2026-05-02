# SkyPilot Vast.ai Integration Fix - PR Documentation

## Pull Request

**PR #9487:** https://github.com/skypilot-org/skypilot/pull/9487
**Title:** [Vast.ai] Fix Vast.ai provider compatibility with SDK v1.0+ (v2)
**Status:** Open (awaiting review)
**Branch:** `fix-vast-ai-integration`
**Fork:** https://github.com/juansanjose/skypilot/tree/fix-vast-ai-integration

## Issues Fixed

### 1. `api_key_access` AttributeError
**Problem:** `vast.vast().api_key_access` doesn't exist in Vast SDK v1.0+
```
AttributeError: 'VastAI' object has no attribute 'api_key_access'
```
**Fix:** Read API key from `~/.config/vastai/vast_api_key` directly

### 2. Unsupported `direct` Parameter
**Problem:** Vast SDK `create_instance()` doesn't accept `direct=True`
```
create_instance() got an unexpected keyword argument 'direct'
```
**Fix:** Remove `direct` parameter from launch_params

### 3. Incorrect SSH Parameter
**Problem:** Vast SDK doesn't accept `ssh=True`, requires `runtype='ssh'`
```
create_instance() got an unexpected keyword argument 'ssh'
```
**Fix:** Use `runtype='ssh'` instead of `ssh=True`

### 4. Wrong `env` Parameter Type
**Problem:** Vast API expects `env` as dict, SkyPilot passes string
```
invalid env type: env must be a dict
```
**Fix:** Convert env string to dict using `shlex.split()`

### 5. Lost Custom Configuration
**Problem:** Overwriting `launch_params` discarded user config
**Fix:** Only remove unsupported params, preserve everything else

### 6. Lost Port Mapping
**Problem:** Port mappings were lost in the env dict conversion
**Fix:** Add port mappings to `extra` parameter as Docker run args

## Files Changed

```diff
sky/provision/vast/utils.py
- 272 lines, 19 deletions, 40 insertions
```

## Key Changes

### Before (Broken)
```python
# This fails - api_key_access doesn't exist
skypilot_onstart = [
    'touch ~/.no_auto_tmux',
    f'echo "{vast.vast().api_key_access}" > ~/.vast_api_key',
]

# This fails - direct and ssh not accepted
launch_params['id'] = instance_touse['id']
launch_params['direct'] = True
launch_params['ssh'] = True

# This fails - env must be dict
launch_params['env'] = '-e __SOURCE=skypilot -e KEY=value'
```

### After (Fixed)
```python
# Read API key from config file
api_key_path = pathlib.Path.home() / '.config' / 'vastai' / 'vast_api_key'
api_key = api_key_path.read_text().strip() if api_key_path.exists() else ''

skypilot_onstart = [
    'touch ~/.no_auto_tmux',
    f'echo "{api_key}" > ~/.vast_api_key',
]

# Remove unsupported params, use runtype instead
launch_params['id'] = instance_touse['id']
launch_params.pop('direct', None)
launch_params.pop('ssh', None)
launch_params['runtype'] = 'ssh'

# Convert env to dict
env_dict = {'__SOURCE': 'skypilot'}
tokens = shlex.split(user_env)
# ... parse tokens into dict
launch_params['env'] = env_dict

# Port mappings go to extra
if ports:
    port_map = ' '.join([f'-p {p}:{p}' for p in ports])
    launch_params['extra'] = f'{existing_extra} {port_map}'.strip()
```

## Testing

Tested with:
- SkyPilot 0.12.1
- Vast SDK 1.0.7  
- Python 3.14
- RTX 4090 GPU instances

Manual verification:
```bash
# Instance creation works
vastai create instance <id> --image pytorch/pytorch --disk 10 --ssh

# GPU accessible
ssh root@<host> -p <port> "nvidia-smi"

# PyTorch CUDA works
ssh root@<host> -p <port> "python3 -c 'import torch; print(torch.cuda.is_available())'"
```

## Known Limitations

1. **SSH Key Injection**: SkyPilot's onstart script still has issues injecting SSH keys properly. Manual key addition may be needed.

2. **Network Connectivity**: GPU instances on Vast.ai cannot reach local k3s services (MLflow/MinIO) without Tailscale VPN or public IP exposure.

3. **Status Detection**: SkyPilot sometimes doesn't detect when instances transition from INIT to UP status correctly.

## Next Steps

1. Wait for SkyPilot maintainers to review and merge PR
2. Test with SkyPilot 0.12.2+ when released
3. Address SSH key injection in a follow-up PR
4. Document Tailscale setup for k3s connectivity

## Migration to RunPod

While waiting for the Vast.ai fix to be merged, the project has migrated to **RunPod** as the primary GPU backend. See:
- `mlops-lab/skypilot/tasks/` - Updated task files using `cloud: runpod`
- `docs/runpod-setup.md` - RunPod configuration guide

The Vast.ai implementation remains in the codebase but requires the above fixes to work correctly with SkyPilot.

## References

- Vast.ai SkyPilot announcement: https://vast.ai/article/vast-ai-gpus-can-now-be-rentend-through-skypilot
- SkyPilot GitHub: https://github.com/skypilot-org/skypilot
- Vast.ai Docs: https://vast.ai/docs/

## Changelog

- **v1** (PR #9486): Initial fix attempt
  - Issues found by code review: overwrote launch_params, lost port mappings, fragile env parsing
  - Status: Closed

- **v2** (PR #9487): Addressed code review feedback
  - Preserves custom configuration
  - Restores template logic
  - Uses shlex.split() for robust parsing
  - Ports moved to extra parameter
  - Status: Open, awaiting review