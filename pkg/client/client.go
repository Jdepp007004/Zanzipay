// Package client provides a Go SDK for interacting with ZanziPay.
package client

import (
	"context"
	"fmt"
)

// Client is the ZanziPay API client.
type Client struct {
	addr   string
	apiKey string
}

// Option configures the client.
type Option func(*Client)

// WithAPIKey sets the API key for authentication.
func WithAPIKey(key string) Option {
	return func(c *Client) { c.apiKey = key }
}

// New creates a new ZanziPay client.
func New(addr string, opts ...Option) *Client {
	c := &Client{addr: addr}
	for _, o := range opts {
		o(c)
	}
	return c
}

// CheckRequest is the input to a permission check.
type CheckRequest struct {
	ResourceType  string
	ResourceID    string
	Permission    string
	SubjectType   string
	SubjectID     string
	CaveatContext map[string]string
	Zookie        string
}

// CheckResponse is the result of a permission check.
type CheckResponse struct {
	Allowed       bool
	Verdict       string
	DecisionToken string
	Reasoning     string
}

// Check performs a permission check against the ZanziPay server.
// In a production client this would use gRPC. This stub uses HTTP.
func (c *Client) Check(ctx context.Context, req CheckRequest) (*CheckResponse, error) {
	_ = ctx
	_ = req
	// Stub: real implementation would call gRPC CheckService
	return &CheckResponse{Allowed: false, Verdict: "DENIED", Reasoning: "stub client"}, nil
}

// WriteTuple writes a single relationship tuple.
func (c *Client) WriteTuple(ctx context.Context, t interface{}) (string, error) {
	_ = ctx
	_ = t
	return "stub-zookie", nil
}

// DeleteTuple deletes a relationship tuple.
func (c *Client) DeleteTuple(ctx context.Context, filter interface{}) (string, error) {
	_ = ctx
	_ = filter
	return "stub-zookie", nil
}

// WriteSchema installs a new authorization schema.
func (c *Client) WriteSchema(ctx context.Context, schema string) error {
	_ = ctx
	if schema == "" {
		return fmt.Errorf("schema cannot be empty")
	}
	return nil
}
