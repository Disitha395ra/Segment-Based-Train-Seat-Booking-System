// src/context/AuthContext.jsx
import { createContext, useContext, useState, useCallback, useEffect } from 'react'
import { authApi } from '../api/endpoints'
import { clearAuth } from '../api/client'

const AuthContext = createContext(null)

export function AuthProvider({ children }) {
  const [user, setUser]       = useState(() => {
    try { return JSON.parse(localStorage.getItem('user')) } catch { return null }
  })
  const [loading, setLoading] = useState(false)
  const [ready, setReady]     = useState(false)

  // Validate stored session on mount
  useEffect(() => {
    const token = localStorage.getItem('accessToken')
    if (token && !user) {
      authApi.me()
        .then((res) => setUser(res.data))
        .catch(() => { clearAuth(); setUser(null) })
        .finally(() => setReady(true))
    } else {
      setReady(true)
    }
  }, [])

  const login = useCallback(async (credentials) => {
    setLoading(true)
    try {
      const res = await authApi.login(credentials)
      const { accessToken, refreshToken, mfaRequired } = res.data
      if (mfaRequired) {
        return { mfaRequired: true }
      }
      localStorage.setItem('accessToken', accessToken)
      localStorage.setItem('refreshToken', refreshToken)
      const profile = await authApi.me()
      setUser(profile.data)
      localStorage.setItem('user', JSON.stringify(profile.data))
      return { success: true }
    } finally {
      setLoading(false)
    }
  }, [])

  const register = useCallback(async (data) => {
    setLoading(true)
    try {
      await authApi.register(data)
      return { success: true }
    } finally {
      setLoading(false)
    }
  }, [])

  const logout = useCallback(async () => {
    const refreshToken = localStorage.getItem('refreshToken')
    try {
      if (refreshToken) await authApi.logout(refreshToken)
    } finally {
      clearAuth()
      setUser(null)
    }
  }, [])

  const isAdmin = user?.role === 'ADMIN' || user?.role === 'SUPERADMIN'

  return (
    <AuthContext.Provider value={{ user, loading, ready, login, register, logout, isAdmin }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used within AuthProvider')
  return ctx
}
