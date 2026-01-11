# read-config

A GitHub Action that reads service configuration from `.skyhook/skyhook.yaml`.

## Description

This action parses the Skyhook configuration file and extracts service-specific settings including:
- Service path
- Deployment repository configuration
- Docker build tool settings (context path, dockerfile path)

## Usage

```yaml
- name: Read service config
  id: config
  uses: skyhook-io/read-config@v1
  with:
    working_directory: code
    service_name: my-service

- name: Build Docker image
  run: |
    docker build \
      -f ${{ steps.config.outputs.dockerfile_path || 'Dockerfile' }} \
      ${{ steps.config.outputs.context_path || '.' }}
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `working_directory` | Path to the repository root containing `.skyhook/skyhook.yaml` | No | `.` |
| `service_name` | Name of the service to look up in the config | Yes | - |
| `config_path` | Path to the skyhook config file relative to working_directory | No | `.skyhook/skyhook.yaml` |

## Outputs

| Output | Description |
|--------|-------------|
| `name` | Service name from config |
| `path` | Service path relative to repo root |
| `deployment_repo` | Separate deployment repository (if configured) |
| `deployment_repo_path` | Path within deployment repository |
| `context_path` | Docker build context path relative to repo root |
| `dockerfile_path` | Dockerfile path relative to repo root |
| `config_found` | Whether the config file was found (`true`/`false`) |
| `service_found` | Whether the service was found in config (`true`/`false`) |

## Config File Format

The action expects a `.skyhook/skyhook.yaml` file with the following structure:

```yaml
services:
  - name: my-service
    path: services/my-service
    deploymentRepo: org/deployment-repo
    deploymentRepoPath: services/my-service
    buildTool:
      docker:
        contextPath: services/my-service
        dockerfilePath: docker/Dockerfile.my-service

  - name: another-service
    path: services/another
    buildTool:
      docker:
        contextPath: .
        # dockerfilePath defaults to {contextPath}/Dockerfile if not specified

environments:
  - name: dev
    clusterName: dev-cluster
    namespace: dev
```

## Example: Build with Dynamic Config

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
        with:
          path: code

      - name: Read service config
        id: config
        uses: skyhook-io/read-config@v1
        with:
          working_directory: code
          service_name: ${{ env.SERVICE_NAME }}

      - name: Build and push Docker image
        uses: skyhook-io/docker-build-push-action@v1
        with:
          # Use config values with fallbacks
          context: code/${{ steps.config.outputs.context_path || env.SERVICE_DIR }}
          dockerfile: code/${{ steps.config.outputs.dockerfile_path || format('{0}/Dockerfile', steps.config.outputs.context_path || env.SERVICE_DIR) }}
          image: ${{ inputs.image }}
```

## Fallback Behavior

If the config file doesn't exist or the service isn't found, all output values will be empty strings. This allows workflows to use fallback values:

```yaml
context: ${{ steps.config.outputs.context_path || '.' }}
dockerfile: ${{ steps.config.outputs.dockerfile_path || 'Dockerfile' }}
```

## License

MIT
