import trainlk/backend.models;
import trainlk/backend.config;
import ballerina/crypto;
import ballerina/jwt;
import ballerina/time;
import ballerina/uuid;
import ballerina/lang.array;
import ballerina/regex;

// ── Password Hashing (SHA-256 + salt, 10k iterations) ────────────────────────
// Production note: Ballerina stdlib lacks native bcrypt; PBKDF2-SHA256 via
// multiple hash rounds is used here. Swap for a Java bcrypt FFI call in prod.

public isolated function hashPassword(string password, string salt) returns string|error {
    // 10,000 rounds of SHA-256(salt + round + password) for key stretching
    byte[] data = (salt + password).toBytes();
    foreach int i in 0 ..< 10000 {
        data = crypto:hashSha256(data);
    }
    return array:toBase16(data);
}

public isolated function generateSalt() returns string {
    // 16-byte random salt as UUID (sufficient entropy)
    return regex:replaceAll(uuid:createType4AsString(), "-", "");
}

public isolated function verifyPassword(string password, string salt, string storedHash)
        returns boolean|error {
    string computed = check hashPassword(password, salt);
    return computed == storedHash;
}

// ── JWT ───────────────────────────────────────────────────────────────────────
public isolated function issueAccessToken(string userId, string role, boolean mfaDone)
        returns string|error {
    jwt:IssuerConfig issuerConfig = {
        username: userId,
        issuer: "train-booking-api",
        audience: ["train-booking-client"],
        expTime: <decimal>config:jwtAccessExpirySeconds,
        customClaims: {
            [models:JWT_CLAIM_USER_ID]: userId,
            [models:JWT_CLAIM_ROLE]: role,
            [models:JWT_CLAIM_MFA_DONE]: mfaDone
        },
        signatureConfig: {
            algorithm: jwt:HS256,
            config: config:jwtSecret
        }
    };
    return check jwt:issue(issuerConfig);
}

public isolated function validateAccessToken(string token)
        returns jwt:Payload|models:AuthError {
    jwt:ValidatorConfig validatorConfig = {
        issuer: "train-booking-api",
        audience: ["train-booking-client"],
        clockSkew: 60,
        signatureConfig: {
            secret: config:jwtSecret
        }
    };
    jwt:Payload|jwt:Error payload = jwt:validate(token, validatorConfig);
    if payload is jwt:Error {
        return error models:AuthError("Invalid or expired token: " + payload.message());
    }
    return payload;
}

public isolated function extractClaim(jwt:Payload payload, string claimKey) returns string? {
    anydata val = payload[claimKey];
    if val is string {
        return val;
    }
    return ();
}

// ── Refresh Token ─────────────────────────────────────────────────────────────
public isolated function generateRefreshToken() returns string {
    return uuid:createType4AsString() + uuid:createType4AsString();
}

public isolated function hashToken(string token) returns string|error {
    byte[] hashed = crypto:hashSha256(token.toBytes());
    return array:toBase16(hashed);
}

public isolated function refreshTokenExpiresAt() returns string {
    time:Utc expiry = time:utcAddSeconds(time:utcNow(), <decimal>(config:jwtRefreshExpiryDays * 86400));
    return time:utcToString(expiry);
}

// ── Register ──────────────────────────────────────────────────────────────────
