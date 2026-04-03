export interface BenchmarkResult {
  system: string
  scenario: string
  p50_ms: number
  p95_ms: number
  p99_ms: number
  throughput_rps: number
  error_rate: number
  operations: number
  concurrency: number
}

export interface SystemFeatures {
  system: string
  rebac: boolean
  abac: boolean
  caveats: boolean
  compliance: boolean
  immutableAudit: boolean
  reverseIndex: boolean
  multiEngine: boolean
  consistency: boolean
  openSource: boolean
  fintechReady: boolean
}
