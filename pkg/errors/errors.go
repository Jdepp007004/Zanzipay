// Package errors defines ZanziPay sentinel errors.
package errors

import (
	"errors"

	"google.golang.org/grpc/codes"
)

var (
	ErrNotFound         = errors.New("not found")
	ErrAlreadyExists    = errors.New("already exists")
	ErrInvalidArgument  = errors.New("invalid argument")
	ErrPermissionDenied = errors.New("permission denied")
	ErrUnauthenticated  = errors.New("unauthenticated")
	ErrInternal         = errors.New("internal error")
	ErrDeadlineExceeded = errors.New("deadline exceeded")
	ErrSchemaInvalid    = errors.New("schema invalid")
	ErrTupleInvalid     = errors.New("tuple invalid")
	ErrZookieInvalid    = errors.New("zookie invalid")
	ErrStorageFull      = errors.New("storage full")

	ErrSanctionsMatch    = errors.New("sanctions list match")
	ErrKYCInsufficient   = errors.New("KYC tier insufficient")
	ErrAccountFrozen     = errors.New("account is frozen")
	ErrRegulatoryBlock   = errors.New("regulatory override active")
	ErrPolicyViolation   = errors.New("policy forbids action")
	ErrCaveatMissing     = errors.New("caveat context missing")
	ErrRateLimited       = errors.New("rate limit exceeded")
)

func ToGRPCStatus(err error) codes.Code {
	switch {
	case errors.Is(err, ErrNotFound): return codes.NotFound
	case errors.Is(err, ErrPermissionDenied): return codes.PermissionDenied
	case errors.Is(err, ErrUnauthenticated): return codes.Unauthenticated
	case errors.Is(err, ErrRateLimited): return codes.ResourceExhausted
	case errors.Is(err, ErrDeadlineExceeded): return codes.DeadlineExceeded
	default: return codes.Internal
	}
}
