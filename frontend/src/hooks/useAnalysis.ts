import { useState, useRef, useCallback } from 'react'
import type { AnalysisResult } from '../types'

const MAX_RETRIES = 150
const POLL_INTERVAL = 800

/** 文件上传 → 轮询状态 → 获取结果 全流程封装 */
export function useAnalysis() {
  const [result, setResult] = useState<AnalysisResult | null>(null)
  const [isAnalyzing, setIsAnalyzing] = useState(false)
  const [progress, setProgress] = useState(0)
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)

  const upload = useCallback(async (file: File) => {
    const formData = new FormData()
    formData.append('file', file)

    setIsAnalyzing(true)
    setProgress(0)

    const res = await fetch('/api/v1/analyze', { method: 'POST', body: formData })
    if (!res.ok) {
      const err = await res.json().catch(() => ({ detail: 'Upload failed' }))
      setIsAnalyzing(false)
      throw new Error(err.detail || 'Upload failed')
    }

    const { task_id } = await res.json()
    pollStatus(task_id)
  }, [])

  const pollStatus = useCallback((id: string) => {
    let retries = 0

    if (pollRef.current) clearInterval(pollRef.current)

    pollRef.current = setInterval(async () => {
      try {
        const res = await fetch(`/api/v1/status/${id}`)
        if (!res.ok) {
          if (++retries >= MAX_RETRIES) {
            clearInterval(pollRef.current!)
            setIsAnalyzing(false)
            alert('Analysis timed out.')
          }
          return
        }

        const data = await res.json()
        retries = 0

        if (data.status === 'processing') {
          setProgress(data.progress)
        } else if (data.status === 'completed') {
          clearInterval(pollRef.current!)
          const resultRes = await fetch(`/api/v1/results/${id}`)
          setResult(await resultRes.json())
          setIsAnalyzing(false)
          setProgress(1)
        } else if (data.status === 'failed') {
          clearInterval(pollRef.current!)
          setIsAnalyzing(false)
          alert('Analysis failed: ' + (data.error || 'Unknown'))
        }
      } catch {
        if (++retries >= MAX_RETRIES) {
          clearInterval(pollRef.current!)
          setIsAnalyzing(false)
          alert('Lost connection to server.')
        }
      }
    }, POLL_INTERVAL)
  }, [])

  const reset = useCallback(() => {
    if (pollRef.current) clearInterval(pollRef.current)
    setResult(null)
    setIsAnalyzing(false)
    setProgress(0)
  }, [])

  return { result, isAnalyzing, progress, upload, reset }
}
