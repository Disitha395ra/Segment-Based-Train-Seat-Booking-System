// src/api/client.js — Axios instance with interceptors for auth + error handling
import axios from 'axios'

const BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:9090'

const api = axios.create({
  baseURL: `${BASE_URL}/api/v1`,
  headers: { 'Content-Type': 'application/json' },
  timeout: 15000,
})

// ── Request interceptor: inject access token ─────────────────────────────────
api.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('accessToken')
    if (token) {
      config.headers.Authorization = `Bearer ${token}`
    }
    config.headers['X-Request-ID'] = crypto.randomUUID()
    return config
  },
  (error) => Promise.reject(error)
)

// ── Response interceptor: handle 401, refresh, standardize errors ─────────────
let isRefreshing = false
let failedQueue = []

const processQueue = (error, token = null) => {
  failedQueue.forEach((prom) => {
    if (error) {
      prom.reject(error)
    } else {
      prom.resolve(token)
    }
  })
  failedQueue = []
}

api.interceptors.response.use(
  (response) => response.data, // unwrap the standard envelope automatically
  async (error) => {
    const originalRequest = error.config

    if (error.response?.status === 401 && !originalRequest._retry) {
      const refreshToken = localStorage.getItem('refreshToken')
      if (!refreshToken) {
        clearAuth()
        window.location.href = '/login'
        return Promise.reject(buildError(error))
      }

      if (isRefreshing) {
        return new Promise((resolve, reject) => {
          failedQueue.push({ resolve, reject })
        })
          .then((token) => {
            originalRequest.headers.Authorization = `Bearer ${token}`
            return api(originalRequest)
          })
          .catch((err) => Promise.reject(err))
      }

      originalRequest._retry = true
      isRefreshing = true

      try {
        const res = await axios.post(`${BASE_URL}/api/v1/auth/refresh`, {
          refreshToken,
        })
        const { accessToken, refreshToken: newRefresh } = res.data.data
        localStorage.setItem('accessToken', accessToken)
        localStorage.setItem('refreshToken', newRefresh)
        api.defaults.headers.common.Authorization = `Bearer ${accessToken}`
        processQueue(null, accessToken)
        originalRequest.headers.Authorization = `Bearer ${accessToken}`
        return api(originalRequest)
      } catch (refreshError) {
        processQueue(refreshError, null)
        clearAuth()
        window.location.href = '/login'
        return Promise.reject(buildError(refreshError))
      } finally {
        isRefreshing = false
      }
    }

    return Promise.reject(buildError(error))
  }
)

function buildError(error) {
  const serverError = error.response?.data?.error
  const message = serverError?.message || error.message || 'An unexpected error occurred'
  const code = serverError?.code || 'NETWORK_ERROR'
  const err = new Error(message)
  err.code = code
  err.status = error.response?.status
  err.details = serverError?.details
  return err
}

function clearAuth() {
  localStorage.removeItem('accessToken')
  localStorage.removeItem('refreshToken')
  localStorage.removeItem('user')
}

export default api
export { BASE_URL, clearAuth }
