# OPA (Open Policy Agent) Policies for Kubernetes
# Policy-as-Code for security and compliance

package kubernetes.admission

# Deny privileged containers
deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    container.securityContext.privileged
    msg := sprintf("Privileged container is not allowed: %v", [container.name])
}

# Require resource limits
deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    not container.resources.limits.cpu
    msg := sprintf("Container %v must have CPU limits", [container.name])
}

deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    not container.resources.limits.memory
    msg := sprintf("Container %v must have memory limits", [container.name])
}

# Deny latest tag
deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    endswith(container.image, ":latest")
    msg := sprintf("Container %v uses 'latest' tag, which is not allowed", [container.name])
}

# Require read-only root filesystem
deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    not container.securityContext.readOnlyRootFilesystem == true
    msg := sprintf("Container %v must use read-only root filesystem", [container.name])
}

# Deny privileged escalation
deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    container.securityContext.allowPrivilegeEscalation
    msg := sprintf("Privilege escalation not allowed for container: %v", [container.name])
}

# Require non-root user
deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    not container.securityContext.runAsNonRoot == true
    msg := sprintf("Container %v must run as non-root user", [container.name])
}

# Require liveness probe
deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    not container.livenessProbe
    msg := sprintf("Container %v must have liveness probe", [container.name])
}

# Require readiness probe
deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    not container.readinessProbe
    msg := sprintf("Container %v must have readiness probe", [container.name])
}

# Deny hostNetwork
deny[msg] {
    input.request.kind.kind == "Pod"
    input.request.object.spec.hostNetwork
    msg := "Host network is not allowed"
}

# Deny hostPID
deny[msg] {
    input.request.kind.kind == "Pod"
    input.request.object.spec.hostPID
    msg := "Host PID namespace is not allowed"
}

# Deny hostIPC
deny[msg] {
    input.request.kind.kind == "Pod"
    input.request.object.spec.hostIPC
    msg := "Host IPC namespace is not allowed"
}

# Require namespace labels
deny[msg] {
    input.request.kind.kind == "Namespace"
    not input.request.object.metadata.labels.team
    msg := "Namespaces must have 'team' label"
}

# Deny services with type LoadBalancer in non-production
deny[msg] {
    input.request.kind.kind == "Service"
    input.request.object.spec.type == "LoadBalancer"
    input.request.namespace != "production"
    msg := "LoadBalancer services only allowed in production namespace"
}

# Require ingress TLS
deny[msg] {
    input.request.kind.kind == "Ingress"
    not input.request.object.spec.tls
    msg := "Ingress must have TLS configured"
}
