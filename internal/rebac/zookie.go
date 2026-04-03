package rebac

import (
	"encoding/base64"
	"encoding/binary"
	"crypto/hmac"
	"crypto/sha256"
	"fmt"
	"time"

	"github.com/Jdepp007004/Zanzipay/internal/storage"
)

// ZookieManager creates and validates zookie tokens.
type ZookieManager struct {
	hmacKey      []byte
	quantization time.Duration
}

// NewZookieManager creates a new manager with the given HMAC key and quantization window.
func NewZookieManager(hmacKey []byte, quantization time.Duration) *ZookieManager {
	return &ZookieManager{hmacKey: hmacKey, quantization: quantization}
}

// Mint creates a new zookie encoding the given revision.
func (zm *ZookieManager) Mint(rev storage.Revision) string {
	payload := make([]byte, 8)
	binary.BigEndian.PutUint64(payload, uint64(rev))
	mac := hmac.New(sha256.New, zm.hmacKey)
	mac.Write(payload)
	sig := mac.Sum(nil)[:6]
	token := append(payload, sig...)
	return base64.URLEncoding.EncodeToString(token)
}

// Decode decodes a zookie to its embedded revision. Returns an error if invalid.
func (zm *ZookieManager) Decode(zookie string) (storage.Revision, error) {
	token, err := base64.URLEncoding.DecodeString(zookie)
	if err != nil {
		return 0, fmt.Errorf("invalid zookie encoding: %w", err)
	}
	if len(token) < 14 {
		return 0, fmt.Errorf("zookie too short")
	}
	payload := token[:8]
	sig := token[8:]

	mac := hmac.New(sha256.New, zm.hmacKey)
	mac.Write(payload)
	expectedSig := mac.Sum(nil)[:6]
	if !hmac.Equal(sig, expectedSig) {
		return 0, fmt.Errorf("zookie signature mismatch")
	}
	rev := int64(binary.BigEndian.Uint64(payload))
	return storage.Revision(rev), nil
}
