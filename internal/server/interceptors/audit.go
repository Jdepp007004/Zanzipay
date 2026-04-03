package interceptors

import (
	"context"
	"time"

	"go.uber.org/zap"
	"google.golang.org/grpc"
)

func AuditInterceptor(log *zap.Logger) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
		start := time.Now()
		resp, err := handler(ctx, req)
		
		fields := []zap.Field{
			zap.String("method", info.FullMethod),
			zap.Duration("dur", time.Since(start)),
			zap.Bool("err", err != nil),
			zap.Any("req", req),
		}

		if err != nil {
			fields = append(fields, zap.Error(err))
		}
		
		if resp != nil {
			fields = append(fields, zap.Any("resp", resp))
		}

		log.Info("grpc_audit", fields...)
		
		return resp, err
	}
}
