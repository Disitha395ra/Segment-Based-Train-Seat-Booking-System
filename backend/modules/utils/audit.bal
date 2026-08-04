// =============================================================================
// audit.bal — Audit logging service (centralized)
// =============================================================================
import trainlk/backend.db;
import ballerina/log;

public isolated function logAudit(
        string actorId, string actorType, string action,
        string? entityType, string? entityId,
        json? oldValue, json? newValue,
        string? ip, string? ua, json metadata) returns error? {
    error? result = db:dbInsertAuditLog(
        actorId == "" ? () : actorId,
        actorType, action, entityType, entityId,
        oldValue, newValue, ip, ua, metadata
    );
    if result !is () {
        log:printWarn("Audit log insert failed", 'error = result,
                      action = action, entityType = entityType ?: "");
    }
}
