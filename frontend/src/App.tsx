import React from 'react'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { Layout } from './components/Layout'
import { Dashboard } from './pages/Dashboard'
import { Latency } from './pages/Latency'
import { Throughput } from './pages/Throughput'
import { Features } from './pages/Features'
import { Architecture } from './pages/Architecture'
import { RawData } from './pages/RawData'

export default function App() {
  return (
    <BrowserRouter>
      <Layout>
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/latency" element={<Latency />} />
          <Route path="/throughput" element={<Throughput />} />
          <Route path="/features" element={<Features />} />
          <Route path="/architecture" element={<Architecture />} />
          <Route path="/raw-data" element={<RawData />} />
        </Routes>
      </Layout>
    </BrowserRouter>
  )
}
