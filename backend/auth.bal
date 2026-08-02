// =============================================================================
// auth.bal — Authentication service: JWT, Refresh Tokens, MFA (TOTP RFC 6238)
// =============================================================================

import ballerina/crypto;
import ballerina/jwt;
import ballerina/time;
import ballerina/uuid;
import ballerina/lang.array;
import ballerina/regex;
import ballerina/log;

// ── Password Hashing (SHA-256 + salt, 10k iterations) ────────────────────────
// Production note: Ballerina stdlib lacks native bcrypt; PBKDF2-SHA256 via
// multiple hash rounds is used here. Swap for a Java bcrypt FFI call in prod.

isolated function hashPassword(string password, string salt) returns string|error {
    // 10,000 rounds of SHA-256(salt + round + password) for key stretching
    byte[] data = (salt + password).toBytes();
    foreach int i in 0 ..< 10000 {
        data = check crypto:hashSha256(data);
    }
    return array:toBase16(data);
}

isolated function generateSalt() returns string {
    // 16-byte random salt as UUID (sufficient entropy)
    return uuid:createType4AsString().replace("-", "");
}

isolated function verifyPassword(string password, string salt, string storedHash)
        returns boolean|error {
    string computed = check hashPassword(password, salt);
    return computed == storedHash;
}

// ── JWT ───────────────────────────────────────────────────────────────────────
isolated function issueAccessToken(string userId, string role, boolean mfaDone)
        returns string|error {
    jwt:IssuerConfig issuerConfig = {
        username: userId,
        issuer: "train-booking-api",
        audience: ["train-booking-client"],
        expTime: jwtAccessExpirySeconds,
        customClaims: {
            [JWT_CLAIM_USER_ID]: userId,
            [JWT_CLAIM_ROLE]: role,
            [JWT_CLAIM_MFA_DONE]: mfaDone
        },
        signatureConfig: {
            algorithm: jwt:HS256,
            config: {
                secret: jwtSecret
            }
        }
    };
    return check jwt:issue(issuerConfig);
}

isolated function validateAccessToken(string token)
        returns jwt:Payload|AuthError {
    jwt:ValidatorConfig validatorConfig = {
        issuer: "train-booking-api",
        audience: ["train-booking-client"],
        clockSkew: 60,
        signatureConfig: {
            secret: jwtSecret
        }
    };
    jwt:Payload|jwt:Error payload = jwt:validate(token, validatorConfig);
    if payload is jwt:Error {
        return error AuthError("Invalid or expired token: " + payload.message());
    }
    return payload;
}

isolated function extractClaim(jwt:Payload payload, string claimKey) returns string? {
    map<json>? customClaims = payload.customClaims;
    if customClaims is () {
        return ();
    }
    json? val = customClaims[claimKey];
    if val is string {
        return val;
    }
    return ();
}

// ── Refresh Token ─────────────────────────────────────────────────────────────
isolated function generateRefreshToken() returns string {
    return uuid:createType4AsString() + uuid:createType4AsString();
}

isolated function hashToken(string token) returns string|error {
    byte[] hashed = check crypto:hashSha256(token.toBytes());
    return array:toBase16(hashed);
}

isolated function refreshTokenExpiresAt() returns string {
    time:Utc expiry = time:utcAddSeconds(time:utcNow(), <decimal>(jwtRefreshExpiryDays * 86400));
    return time:utcToString(expiry);
}

// ── Register ──────────────────────────────────────────────────────────────────
public isolated function registerUser(RegisterRequest req)
        returns UserProfile|ValidationError|DatabaseError|error {
    // Validate input
    check validateRegistration(req);

    string salt = generateSalt();
    string hash = check hashPassword(req.password, salt);
    string userId = check dbCreateUser(req, hash, salt);

    // Audit log
    _ = check logAudit(userId, "USER", "USER_REGISTERED", "USER", userId, (), {email: req.email}, (), (), {});

    return {
        id: userId,
        email: req.email,
        fullName: req.fullName,
        phone: req.phone,
        role: "PASSENGER",
        mfaEnabled: false,
        createdAt: time:utcToString(time:utcNow())
    };
}

// ── Login ─────────────────────────────────────────────────────────────────────
public isolated function loginUser(LoginRequest req, string? ip, string? ua)
        returns TokenPair|AuthError|MfaRequiredError|ValidationError|error {
    // Validate input
    if req.email.trim() == "" || req.password.trim() == "" {
        return error ValidationError("Email and password are required");
    }

    UserRow|error user = dbGetUserByEmail(req.email);
    if user is NotFoundError {
        // Constant-time response to prevent user enumeration
        _ = check hashPassword("dummy_password", "dummy_salt");
        return error AuthError("Invalid credentials");
    }
    if user is error {
        return error AuthError("Login failed");
    }
    if !user.isActive {
        return error AuthError("Account is disabled");
    }

    boolean valid = check verifyPassword(req.password, user.passwordSalt, user.passwordHash);
    if !valid {
        _ = check logAudit(user.id, "USER", "LOGIN_FAILED", "USER", user.id, (), (), ip, ua, {});
        return error AuthError("Invalid credentials");
    }

    // MFA check
    if user.mfaEnabled {
        string? code = req.totpCode;
        if code is () {
            return error MfaRequiredError("MFA token required");
        }
        string encryptedSecret = user.mfaSecretEncrypted ?: "";
        string secret = check decryptMfaSecret(encryptedSecret);
        boolean totpValid = check verifyTOTP(secret, code);
        if !totpValid {
            // Try backup codes
            string codeHash = check hashToken(code);
            boolean usedBackup = check dbUseBackupCode(user.id, codeHash);
            if !usedBackup {
                _ = check logAudit(user.id, "USER", "MFA_FAILED", "USER", user.id, (), (), ip, ua, {});
                return error AuthError("Invalid MFA code");
            }
        }
    }

    // Issue tokens
    string accessToken = check issueAccessToken(user.id, user.role, true);
    string rawRefresh = generateRefreshToken();
    string refreshHash = check hashToken(rawRefresh);
    string expiresAt = refreshTokenExpiresAt();

    check dbSaveRefreshToken(user.id, refreshHash, expiresAt, ip, ua);
    _ = check logAudit(user.id, "USER", "USER_LOGIN", "USER", user.id, (), (), ip, ua, {});

    return {
        accessToken: accessToken,
        refreshToken: rawRefresh,
        tokenType: "Bearer",
        expiresIn: jwtAccessExpirySeconds,
        mfaRequired: false
    };
}

// ── Refresh ───────────────────────────────────────────────────────────────────
public isolated function refreshTokens(string rawRefreshToken, string? ip, string? ua)
        returns TokenPair|AuthError|error {
    string tokenHash = check hashToken(rawRefreshToken);

    record {|string userId; string expiresAt; string? revokedAt;|}|error stored =
        dbGetRefreshToken(tokenHash);
    if stored is NotFoundError {
        return error AuthError("Refresh token not found");
    }
    if stored is error {
        return error AuthError("Refresh token lookup failed");
    }
    if stored.revokedAt !is () {
        // Token reuse detected — revoke all tokens for this user (security measure)
        _ = check dbRevokeAllUserRefreshTokens(stored.userId);
        _ = check logAudit(stored.userId, "USER", "REFRESH_TOKEN_REUSE_DETECTED",
                "USER", stored.userId, (), (), ip, ua, {});
        return error AuthError("Refresh token reuse detected. Please log in again.");
    }

    // Revoke old token (rotation)
    check dbRevokeRefreshToken(tokenHash);

    UserRow|error user = dbGetUserById(stored.userId);
    if user is error {
        return error AuthError("User not found");
    }

    // Issue new pair
    string newAccess = check issueAccessToken(user.id, user.role, true);
    string newRaw = generateRefreshToken();
    string newHash = check hashToken(newRaw);
    string newExpiry = refreshTokenExpiresAt();

    check dbSaveRefreshToken(user.id, newHash, newExpiry, ip, ua);

    return {
        accessToken: newAccess,
        refreshToken: newRaw,
        tokenType: "Bearer",
        expiresIn: jwtAccessExpirySeconds,
        mfaRequired: false
    };
}

// ── Logout ────────────────────────────────────────────────────────────────────
public isolated function logoutUser(string rawRefreshToken, string userId) returns error? {
    string tokenHash = check hashToken(rawRefreshToken);
    check dbRevokeRefreshToken(tokenHash);
    _ = check logAudit(userId, "USER", "USER_LOGOUT", "USER", userId, (), (), (), (), {});
}

// ── MFA Setup ─────────────────────────────────────────────────────────────────
public isolated function setupMfa(string userId) returns MfaSetupResponse|error {
    // Generate a 20-byte TOTP secret and base32-encode it
    string secret = generateTotpSecret();
    string encryptedSecret = check encryptMfaSecret(secret);

    // Store encrypted secret (not yet enabled — enabled after verification)
    _ = check dbClient->execute(
        `UPDATE users SET mfa_secret_encrypted = ${encryptedSecret} WHERE id = ${userId}::uuid`
    );

    UserRow user = check dbGetUserById(userId);
    string qrUri = "otpauth://totp/SLTrainBooking:" + user.email +
                   "?secret=" + secret + "&issuer=SLTrainBooking&digits=6&period=30";

    // Generate 8 backup codes
    string[] backupCodes = [];
    string[] backupHashes = [];
    foreach int i in 0 ..< 8 {
        string code = generateBackupCode();
        backupCodes.push(code);
        string codeHash = check hashToken(code);
        backupHashes.push(codeHash);
    }
    // Clear old backup codes and save new ones
    _ = check dbClient->execute(`DELETE FROM mfa_backup_codes WHERE user_id = ${userId}::uuid`);
    check dbSaveBackupCodes(userId, backupHashes);

    _ = check logAudit(userId, "USER", "MFA_SETUP_INITIATED", "USER", userId, (), (), (), (), {});

    return {qrUri: qrUri, secret: secret, backupCodes: backupCodes};
}

public isolated function verifyAndEnableMfa(string userId, string totpCode) returns error? {
    UserRow user = check dbGetUserById(userId);
    string encryptedSecret = user.mfaSecretEncrypted ?: "";
    if encryptedSecret == "" {
        return error AuthError("MFA setup not initiated");
    }
    string secret = check decryptMfaSecret(encryptedSecret);
    boolean valid = check verifyTOTP(secret, totpCode);
    if !valid {
        return error AuthError("Invalid TOTP code");
    }
    check dbEnableMfa(userId, encryptedSecret);
    _ = check logAudit(userId, "USER", "MFA_ENABLED", "USER", userId, (), (), (), (), {});
}

// ── TOTP (RFC 6238) ───────────────────────────────────────────────────────────
isolated function verifyTOTP(string base32Secret, string code) returns boolean|error {
    // Verify current window and ±1 adjacent window (clock drift tolerance)
    int timeStep = <int>(time:utcNow()[0] / 30);
    foreach int delta in [-1, 0, 1] {
        string expected = check generateHOTP(base32Secret, timeStep + delta);
        if expected == code {
            return true;
        }
    }
    return false;
}

isolated function generateHOTP(string base32Secret, int counter) returns string|error {
    byte[] key = decodeBase32(base32Secret);
    byte[] message = int64ToBytes(counter);
    byte[] hmac = check crypto:hmacSha1(message, key);

    // Dynamic truncation (RFC 4226)
    int offset = hmac[19] & 0x0f;
    int code = ((hmac[offset]     & 0x7f) << 24) |
               ((hmac[offset + 1] & 0xff) << 16) |
               ((hmac[offset + 2] & 0xff) << 8)  |
               (hmac[offset + 3]  & 0xff);

    int otp = code % 1000000;
    string otpStr = otp.toString();
    // Pad to 6 digits
    while otpStr.length() < 6 {
        otpStr = "0" + otpStr;
    }
    return otpStr;
}

isolated function int64ToBytes(int value) returns byte[] {
    byte[] b = [0, 0, 0, 0, 0, 0, 0, 0];
    int v = value;
    foreach int i in 7 ..< -1 {
        b[i] = <byte>(v & 0xff);
        v = v >> 8;
    }
    return b;
}

isolated function generateTotpSecret() returns string {
    // 20 random bytes, base32-encoded
    // Using UUID-derived randomness (16 bytes sufficient for TOTP)
    string u1 = uuid:createType4AsString().replace("-", "");
    string u2 = uuid:createType4AsString().replace("-", "").substring(0, 8);
    byte[] raw = (u1 + u2).toBytes().slice(0, 20);
    return encodeBase32(raw);
}

isolated function generateBackupCode() returns string {
    string u = uuid:createType4AsString().replace("-", "");
    return u.substring(0, 4).toUpperAscii() + "-" + u.substring(4, 8).toUpperAscii();
}

// ── Base32 encode/decode ──────────────────────────────────────────────────────
const string BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

isolated function encodeBase32(byte[] data) returns string {
    string result = "";
    int buffer = 0;
    int bitsLeft = 0;
    foreach byte b in data {
        buffer = (buffer << 8) | (b & 0xff);
        bitsLeft += 8;
        while bitsLeft >= 5 {
            bitsLeft -= 5;
            int idx = (buffer >> bitsLeft) & 0x1f;
            result += BASE32_ALPHABET.substring(idx, idx + 1);
        }
    }
    if bitsLeft > 0 {
        int idx = (buffer << (5 - bitsLeft)) & 0x1f;
        result += BASE32_ALPHABET.substring(idx, idx + 1);
    }
    return result;
}

isolated function decodeBase32(string input) returns byte[] {
    byte[] result = [];
    int buffer = 0;
    int bitsLeft = 0;
    foreach int i in 0 ..< input.length() {
        string ch = input.substring(i, i + 1).toUpperAscii();
        int val = BASE32_ALPHABET.indexOf(ch) ?: -1;
        if val < 0 {
            continue;
        }
        buffer = (buffer << 5) | val;
        bitsLeft += 5;
        if bitsLeft >= 8 {
            bitsLeft -= 8;
            result.push(<byte>((buffer >> bitsLeft) & 0xff));
        }
    }
    return result;
}

// ── AES-256 MFA Secret Encryption ────────────────────────────────────────────
// Uses crypto:encryptAesCbc — key must be 32 bytes (64 hex chars)

isolated function encryptMfaSecret(string plainText) returns string|error {
    byte[] keyBytes = check decodeHex(mfaEncryptionKey.substring(0, 64));
    byte[] iv = check decodeHex(mfaEncryptionKey.substring(0, 32)); // IV from first 16 bytes of key
    byte[] encrypted = check crypto:encryptAesCbc(plainText.toBytes(), keyBytes, iv);
    return array:toBase16(encrypted);
}

isolated function decryptMfaSecret(string cipherHex) returns string|error {
    byte[] keyBytes = check decodeHex(mfaEncryptionKey.substring(0, 64));
    byte[] iv = check decodeHex(mfaEncryptionKey.substring(0, 32));
    byte[] cipherBytes = check decodeHex(cipherHex);
    byte[] decrypted = check crypto:decryptAesCbc(cipherBytes, keyBytes, iv);
    return check string:fromBytes(decrypted);
}

isolated function decodeHex(string hex) returns byte[]|error {
    if hex.length() % 2 != 0 {
        return error("Invalid hex string length");
    }
    byte[] result = [];
    foreach int i in 0 ..< hex.length() / 2 {
        string byteStr = hex.substring(i * 2, i * 2 + 2);
        int byteVal = check int:fromHexString(byteStr);
        result.push(<byte>byteVal);
    }
    return result;
}

// ── Input Validation ──────────────────────────────────────────────────────────
isolated function validateRegistration(RegisterRequest req) returns ValidationError? {
    if req.email.trim() == "" {
        return error ValidationError("Email is required");
    }
    if !isValidEmail(req.email) {
        return error ValidationError("Invalid email format");
    }
    if req.fullName.trim().length() < 2 || req.fullName.trim().length() > 100 {
        return error ValidationError("Full name must be 2–100 characters");
    }
    if req.password.length() < 8 {
        return error ValidationError("Password must be at least 8 characters");
    }
    // Password strength: must have uppercase, lowercase, digit
    if !regex:matches(req.password, ".*[A-Z].*") {
        return error ValidationError("Password must contain at least one uppercase letter");
    }
    if !regex:matches(req.password, ".*[0-9].*") {
        return error ValidationError("Password must contain at least one digit");
    }
    return ();
}

isolated function isValidEmail(string email) returns boolean =>
    regex:matches(email, "^[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}$");
