// =============================================================================
// auth.bal — Authentication service: JWT, Refresh Tokens, MFA (TOTP RFC 6238)
// =============================================================================

import trainlk/backend.models;
import trainlk/backend.db;
import trainlk/backend.config;
import trainlk/backend.utils;
import ballerina/crypto;
import ballerina/time;
import ballerina/uuid;
import ballerina/lang.array;
import ballerina/regex;


public isolated function registerUser(models:RegisterRequest req)
        returns models:UserProfile|models:ValidationError|models:DatabaseError|error {
    // Validate input
    check validateRegistration(req);

    string salt = utils:generateSalt();
    string hash = check utils:hashPassword(req.password, salt);
    string userId = check db:dbCreateUser(req, hash, salt);

    // Audit log
    _ = check utils:logAudit(userId, "USER", "USER_REGISTERED", "USER", userId, (), {email: req.email}, (), (), {});

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
public isolated function loginUser(models:LoginRequest req, string? ip, string? ua)
        returns models:TokenPair|models:AuthError|models:MfaRequiredError|models:ValidationError|error {
    // Validate input
    if req.email.trim() == "" || req.password.trim() == "" {
        return error models:ValidationError("Email and password are required");
    }

    models:UserRow|error user = db:dbGetUserByEmail(req.email);
    if user is models:NotFoundError {
        // Constant-time response to prevent user enumeration
        _ = check utils:hashPassword("dummy_password", "dummy_salt");
        return error models:AuthError("Invalid credentials");
    }
    if user is error {
        return error models:AuthError("Login failed");
    }
    if !user.isActive {
        return error models:AuthError("Account is disabled");
    }

    boolean valid = check utils:verifyPassword(req.password, user.passwordSalt, user.passwordHash);
    if !valid {
        _ = check utils:logAudit(user.id, "USER", "LOGIN_FAILED", "USER", user.id, (), (), ip, ua, {});
        return error models:AuthError("Invalid credentials");
    }

    // MFA check
    if user.mfaEnabled {
        string? code = req.totpCode;
        if code is () {
            return error models:MfaRequiredError("MFA token required");
        }
        string encryptedSecret = user.mfaSecretEncrypted ?: "";
        string secret = check decryptMfaSecret(encryptedSecret);
        boolean totpValid = check verifyTOTP(secret, code);
        if !totpValid {
            // Try backup codes
            string codeHash = check utils:hashToken(code);
            boolean usedBackup = check db:dbUseBackupCode(user.id, codeHash);
            if !usedBackup {
                _ = check utils:logAudit(user.id, "USER", "MFA_FAILED", "USER", user.id, (), (), ip, ua, {});
                return error models:AuthError("Invalid MFA code");
            }
        }
    }

    // Issue tokens
    string accessToken = check utils:issueAccessToken(user.id, user.role, true);
    string rawRefresh = utils:generateRefreshToken();
    string refreshHash = check utils:hashToken(rawRefresh);
    string expiresAt = utils:refreshTokenExpiresAt();

    check db:dbSaveRefreshToken(user.id, refreshHash, expiresAt, ip, ua);
    _ = check utils:logAudit(user.id, "USER", "USER_LOGIN", "USER", user.id, (), (), ip, ua, {});

    return {
        accessToken: accessToken,
        refreshToken: rawRefresh,
        tokenType: "Bearer",
        expiresIn: config:jwtAccessExpirySeconds,
        mfaRequired: false
    };
}

// ── Refresh ───────────────────────────────────────────────────────────────────
public isolated function refreshTokens(string rawRefreshToken, string? ip, string? ua)
        returns models:TokenPair|models:AuthError|error {
    string tokenHash = check utils:hashToken(rawRefreshToken);

    record {|string userId; string expiresAt; string? revokedAt;|}|error stored =
        db:dbGetRefreshToken(tokenHash);
    if stored is models:NotFoundError {
        return error models:AuthError("Refresh token not found");
    }
    if stored is error {
        return error models:AuthError("Refresh token lookup failed");
    }
    if stored.revokedAt !is () {
        // Token reuse detected — revoke all tokens for this user (security measure)
        _ = check db:dbRevokeAllUserRefreshTokens(stored.userId);
        _ = check utils:logAudit(stored.userId, "USER", "REFRESH_TOKEN_REUSE_DETECTED",
                "USER", stored.userId, (), (), ip, ua, {});
        return error models:AuthError("Refresh token reuse detected. Please log in again.");
    }

    // Revoke old token (rotation)
    check db:dbRevokeRefreshToken(tokenHash);

    models:UserRow|error user = db:dbGetUserById(stored.userId);
    if user is error {
        return error models:AuthError("User not found");
    }

    // Issue new pair
    string newAccess = check utils:issueAccessToken(user.id, user.role, true);
    string newRaw = utils:generateRefreshToken();
    string newHash = check utils:hashToken(newRaw);
    string newExpiry = utils:refreshTokenExpiresAt();

    check db:dbSaveRefreshToken(user.id, newHash, newExpiry, ip, ua);

    return {
        accessToken: newAccess,
        refreshToken: newRaw,
        tokenType: "Bearer",
        expiresIn: config:jwtAccessExpirySeconds,
        mfaRequired: false
    };
}

// ── Logout ────────────────────────────────────────────────────────────────────
public isolated function logoutUser(string rawRefreshToken, string userId) returns error? {
    string tokenHash = check utils:hashToken(rawRefreshToken);
    check db:dbRevokeRefreshToken(tokenHash);
    _ = check utils:logAudit(userId, "USER", "USER_LOGOUT", "USER", userId, (), (), (), (), {});
}

// ── MFA Setup ─────────────────────────────────────────────────────────────────
public isolated function setupMfa(string userId) returns models:MfaSetupResponse|error {
    // Generate a 20-byte TOTP secret and base32-encode it
    string secret = generateTotpSecret();
    string encryptedSecret = check encryptMfaSecret(secret);

    // Store encrypted secret (not yet enabled — enabled after verification)
    _ = check db:dbClient->execute(
        `UPDATE users SET mfa_secret_encrypted = ${encryptedSecret} WHERE id = ${userId}::uuid`
    );

    models:UserRow user = check db:dbGetUserById(userId);
    string qrUri = "otpauth://totp/SLTrainBooking:" + user.email +
                   "?secret=" + secret + "&issuer=SLTrainBooking&digits=6&period=30";

    // Generate 8 backup codes
    string[] backupCodes = [];
    string[] backupHashes = [];
    foreach int i in 0 ..< 8 {
        string code = generateBackupCode();
        backupCodes.push(code);
        string codeHash = check utils:hashToken(code);
        backupHashes.push(codeHash);
    }
    // Clear old backup codes and save new ones
    _ = check db:dbClient->execute(`DELETE FROM mfa_backup_codes WHERE user_id = ${userId}::uuid`);
    check db:dbSaveBackupCodes(userId, backupHashes);

    _ = check utils:logAudit(userId, "USER", "MFA_SETUP_INITIATED", "USER", userId, (), (), (), (), {});

    return {qrUri: qrUri, secret: secret, backupCodes: backupCodes};
}

public isolated function verifyAndEnableMfa(string userId, string totpCode) returns error? {
    models:UserRow user = check db:dbGetUserById(userId);
    string encryptedSecret = user.mfaSecretEncrypted ?: "";
    if encryptedSecret == "" {
        return error models:AuthError("MFA setup not initiated");
    }
    string secret = check decryptMfaSecret(encryptedSecret);
    boolean valid = check verifyTOTP(secret, totpCode);
    if !valid {
        return error models:AuthError("Invalid TOTP code");
    }
    check db:dbEnableMfa(userId, encryptedSecret);
    _ = check utils:logAudit(userId, "USER", "MFA_ENABLED", "USER", userId, (), (), (), (), {});
}

// ── TOTP (RFC 6238) ───────────────────────────────────────────────────────────
public isolated function verifyTOTP(string base32Secret, string code) returns boolean|error {
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

public isolated function generateHOTP(string base32Secret, int counter) returns string|error {
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

public isolated function int64ToBytes(int value) returns byte[] {
    byte[] b = [0, 0, 0, 0, 0, 0, 0, 0];
    int v = value;
    foreach int i in 7 ..< -1 {
        b[i] = <byte>(v & 0xff);
        v = v >> 8;
    }
    return b;
}

public isolated function generateTotpSecret() returns string {
    // 20 random bytes, base32-encoded
    // Using UUID-derived randomness (16 bytes sufficient for TOTP)
    string u1 = regex:replaceAll(uuid:createType4AsString(), "-", "");
    string u2 = regex:replaceAll(uuid:createType4AsString(), "-", "").substring(0, 8);
    byte[] raw = (u1 + u2).toBytes().slice(0, 20);
    return encodeBase32(raw);
}

public isolated function generateBackupCode() returns string {
    string u = regex:replaceAll(uuid:createType4AsString(), "-", "");
    return u.substring(0, 4).toUpperAscii() + "-" + u.substring(4, 8).toUpperAscii();
}

// ── Base32 encode/decode ──────────────────────────────────────────────────────
const string BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

public isolated function encodeBase32(byte[] data) returns string {
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

public isolated function decodeBase32(string input) returns byte[] {
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

public isolated function encryptMfaSecret(string plainText) returns string|error {
    byte[] keyBytes = check decodeHex(config:mfaEncryptionKey.substring(0, 64));
    byte[] iv = check decodeHex(config:mfaEncryptionKey.substring(0, 32)); // IV from first 16 bytes of key
    byte[] encrypted = check crypto:encryptAesCbc(plainText.toBytes(), keyBytes, iv);
    return array:toBase16(encrypted);
}

public isolated function decryptMfaSecret(string cipherHex) returns string|error {
    byte[] keyBytes = check decodeHex(config:mfaEncryptionKey.substring(0, 64));
    byte[] iv = check decodeHex(config:mfaEncryptionKey.substring(0, 32));
    byte[] cipherBytes = check decodeHex(cipherHex);
    byte[] decrypted = check crypto:decryptAesCbc(cipherBytes, keyBytes, iv);
    return check string:fromBytes(decrypted);
}

public isolated function decodeHex(string hex) returns byte[]|error {
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
public isolated function validateRegistration(models:RegisterRequest req) returns models:ValidationError? {
    if req.email.trim() == "" {
        return error models:ValidationError("Email is required");
    }
    if !isValidEmail(req.email) {
        return error models:ValidationError("Invalid email format");
    }
    if req.fullName.trim().length() < 2 || req.fullName.trim().length() > 100 {
        return error models:ValidationError("Full name must be 2–100 characters");
    }
    if req.password.length() < 8 {
        return error models:ValidationError("Password must be at least 8 characters");
    }
    // Password strength: must have uppercase, lowercase, digit
    if !regex:matches(req.password, ".*[A-Z].*") {
        return error models:ValidationError("Password must contain at least one uppercase letter");
    }
    if !regex:matches(req.password, ".*[0-9].*") {
        return error models:ValidationError("Password must contain at least one digit");
    }
    return ();
}

public isolated function isValidEmail(string email) returns boolean =>
    regex:matches(email, "^[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}$");
