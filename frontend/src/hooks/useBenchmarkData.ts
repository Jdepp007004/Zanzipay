import { useState, useEffect } from 'react'
import { BenchmarkResult, SystemFeatures } from '../types/benchmark'
import sampleData from '../data/sample-results.json'

interface BenchmarkData {
  results: BenchmarkResult[]
  features: SystemFeatures[]
  scenarios: string[]
  systems: string[]
  loading: boolean
  error: string | null
}

export const useBenchmarkData = (): BenchmarkData => {
  const [data, setData] = useState<Omit<BenchmarkData, 'loading' | 'error'>>({
    results: [], features: [], scenarios: [], systems: [],
  })
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    try {
      const results = sampleData.results as BenchmarkResult[]
      const features = sampleData.features as SystemFeatures[]
      const scenarios = [...new Set(results.map(r => r.scenario))]
      const systems = [...new Set(results.map(r => r.system))]
      setData({ results, features, scenarios, systems })
    } catch {
      setError('Failed to load benchmark data')
    } finally {
      setLoading(false)
    }
  }, [])

  return { ...data, loading, error }
}
