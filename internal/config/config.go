// Package config handles ZanziPay configuration loading and validation.
package config

import (
	"fmt"
	"time"

	"github.com/spf13/viper"
)

// Config is the root configuration structure.
type Config struct {
	Server     ServerConfig     `mapstructure:"server"`
	Storage    StorageConfig    `mapstructure:"storage"`
	ReBAC      ReBACConfig      `mapstructure:"rebac"`
	Policy     PolicyConfig     `mapstructure:"policy"`
	Compliance ComplianceConfig `mapstructure:"compliance"`
	Index      IndexConfig      `mapstructure:"index"`
	Audit      AuditConfig      `mapstructure:"audit"`
	Metrics    MetricsConfig    `mapstructure:"metrics"`
}

// ServerConfig holds HTTP/gRPC server settings.
type ServerConfig struct {
	GRPCPort       int           `mapstructure:"grpc_port"`
	RESTPort       int           `mapstructure:"rest_port"`
	MaxConnections int           `mapstructure:"max_connections"`
	RequestTimeout time.Duration `mapstructure:"request_timeout"`
	APIKeys        []string      `mapstructure:"api_keys"`
}

// StorageConfig configures the storage backend.
type StorageConfig struct {
	Engine   string         `mapstructure:"engine"` // memory | postgres | cockroach
	Postgres PostgresConfig `mapstructure:"postgres"`
}

// PostgresConfig holds PostgreSQL connection settings.
type PostgresConfig struct {
	DSN            string        `mapstructure:"dsn"`
	MaxConnections int           `mapstructure:"max_connections"`
	QueryTimeout   time.Duration `mapstructure:"query_timeout"`
}

// ReBACConfig holds ReBAC engine settings.
type ReBACConfig struct {
	CacheSize           int           `mapstructure:"cache_size"`
	CaveatTimeout       time.Duration `mapstructure:"caveat_timeout"`
	DefaultConsistency  string        `mapstructure:"default_consistency"`
	ZookieQuantization  time.Duration `mapstructure:"zookie_quantization"`
	ZookieHMACKey       string        `mapstructure:"zookie_hmac_key"`
}

// PolicyConfig holds Cedar policy engine settings.
type PolicyConfig struct {
	AutoAnalyze           bool          `mapstructure:"auto_analyze"`
	EvaluationTimeout     time.Duration `mapstructure:"evaluation_timeout"`
	CacheCompiledPolicies bool          `mapstructure:"cache_compiled_policies"`
}

// ComplianceConfig holds compliance engine settings.
type ComplianceConfig struct {
	SanctionsUpdateInterval time.Duration `mapstructure:"sanctions_update_interval"`
	KYCCacheTTL             time.Duration `mapstructure:"kyc_cache_ttl"`
	FreezeCheckEnabled      bool          `mapstructure:"freeze_check_enabled"`
}

// IndexConfig holds materialized index settings.
type IndexConfig struct {
	Enabled              bool          `mapstructure:"enabled"`
	FullRebuildInterval  time.Duration `mapstructure:"full_rebuild_interval"`
	BitmapShardCount     int           `mapstructure:"bitmap_shard_count"`
}

// AuditConfig holds audit logger settings.
type AuditConfig struct {
	BufferSize    int           `mapstructure:"buffer_size"`
	FlushInterval time.Duration `mapstructure:"flush_interval"`
	RetentionDays int           `mapstructure:"retention_days"`
	Immutable     bool          `mapstructure:"immutable"`
}

// MetricsConfig holds Prometheus metrics settings.
type MetricsConfig struct {
	PrometheusPort int  `mapstructure:"prometheus_port"`
	Enabled        bool `mapstructure:"enabled"`
}

// Load reads configuration from the given file path.
func Load(path string) (*Config, error) {
	v := viper.New()
	v.SetConfigFile(path)
	setDefaults(v)
	v.AutomaticEnv()
	v.SetEnvPrefix("ZANZIPAY")

	if err := v.ReadInConfig(); err != nil {
		return nil, fmt.Errorf("reading config %q: %w", path, err)
	}

	cfg := &Config{}
	if err := v.Unmarshal(cfg); err != nil {
		return nil, fmt.Errorf("unmarshalling config: %w", err)
	}
	return cfg, nil
}

// LoadDefaults returns a configuration with sensible defaults.
func LoadDefaults() *Config {
	return &Config{
		Server: ServerConfig{GRPCPort: 50053, RESTPort: 8090, MaxConnections: 1000, RequestTimeout: 100 * time.Millisecond},
		Storage: StorageConfig{Engine: "memory"},
		ReBAC: ReBACConfig{
			CacheSize: 100000, CaveatTimeout: 10 * time.Millisecond,
			ZookieQuantization: 5 * time.Second,
			ZookieHMACKey:      "changeme-hmac-key-at-least-32-bytes-long!!",
		},
		Audit:   AuditConfig{BufferSize: 10000, FlushInterval: time.Second, RetentionDays: 2555, Immutable: true},
		Metrics: MetricsConfig{PrometheusPort: 9090, Enabled: true},
	}
}

func setDefaults(v *viper.Viper) {
	v.SetDefault("server.grpc_port", 50053)
	v.SetDefault("server.rest_port", 8090)
	v.SetDefault("server.max_connections", 1000)
	v.SetDefault("storage.engine", "memory")
	v.SetDefault("rebac.cache_size", 100000)
	v.SetDefault("audit.buffer_size", 10000)
	v.SetDefault("audit.retention_days", 2555)
}
