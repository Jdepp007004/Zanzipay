package interceptors

import (
	"context"
	"fmt"

	"go.uber.org/zap"
	"google.golang.org/grpc"
)

func RecoveryInterceptor(log *zap.Logger) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (resp interface{}, err error) {
		defer func() {
			if r := recover(); r != nil {
				log.Error("panic", zap.Any("recover", r), zap.String("method", info.FullMethod))
				err = fmt.Errorf("internal server error")
			}
		}()
		return handler(ctx, req)
	}
}
