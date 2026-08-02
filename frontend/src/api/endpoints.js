// src/api/endpoints.js — All API call functions, organized by domain
import api, { BASE_URL } from './client'
import axios from 'axios'

// ── Auth ──────────────────────────────────────────────────────────────────────
export const authApi = {
  register: (data) => api.post('/auth/register', data),
  login:    (data) => api.post('/auth/login', data),
  refresh:  (refreshToken) => api.post('/auth/refresh', { refreshToken }),
  logout:   (refreshToken) => api.post('/auth/logout', { refreshToken }),
  me:       () => api.get('/auth/me'),
  mfaSetup: () => api.post('/auth/mfa/setup'),
  mfaVerify:(totpCode) => api.post('/auth/mfa/verify', { totpCode }),
}

// ── Stations ──────────────────────────────────────────────────────────────────
export const stationsApi = {
  list: (page = 1, limit = 50) =>
    api.get('/stations', { params: { page, limit } }),
}

// ── Trains ────────────────────────────────────────────────────────────────────
export const trainsApi = {
  list: () => api.get('/trains'),
  coaches: (trainId) => api.get(`/trains/${trainId}/coaches`),
  seatAvailability: (trainId, from, to, date) =>
    api.get(`/trains/${trainId}/seats/availability`, {
      params: { from, to, date },
    }),
}

// ── Fare ──────────────────────────────────────────────────────────────────────
export const fareApi = {
  estimate: (from, to, coachClass, date) =>
    api.get('/fare/estimate', { params: { from, to, coachClass, date } }),
}

// ── Bookings ──────────────────────────────────────────────────────────────────
export const bookingsApi = {
  create:  (data) => api.post('/bookings', data),
  list:    (page = 1, limit = 20) =>
    api.get('/bookings', { params: { page, limit } }),
  getById: (id) => api.get(`/bookings/${id}`),
  getByRef:(ref) => api.get(`/bookings/ref/${ref}`),
  confirm: (id) => api.post(`/bookings/${id}/confirm`),
  cancel:  (id) => api.delete(`/bookings/${id}`),
}

// ── Waitlist ──────────────────────────────────────────────────────────────────
export const waitlistApi = {
  join: (data) => api.post('/waitlist', data),
}

// ── Admin ─────────────────────────────────────────────────────────────────────
export const adminApi = {
  occupancy: (date) =>
    api.get('/admin/occupancy', { params: { date } }),
  revenue: (from, to, page = 1, limit = 20) =>
    api.get('/admin/revenue', { params: { from, to, page, limit } }),
  audit: (entityType, entityId, page = 1, limit = 50) =>
    api.get('/admin/audit', {
      params: {
        entityType: entityType || undefined,
        entityId:   entityId   || undefined,
        page,
        limit,
      },
    }),
}

// ── Health ────────────────────────────────────────────────────────────────────
export const healthApi = {
  check: () => axios.get(`${BASE_URL}/health`).then((r) => r.data),
}
