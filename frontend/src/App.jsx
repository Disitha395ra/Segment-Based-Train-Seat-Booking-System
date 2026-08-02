import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { AuthProvider, useAuth } from './context/AuthContext'
import { ToastProvider } from './components/common/Toast/ToastContext'
import Layout from './components/Layout/Layout'
import HomePage from './pages/HomePage'
import SeatsPage from './pages/SeatsPage'
import BookingPage from './pages/BookingPage'
import ConfirmationPage from './pages/ConfirmationPage'
import LoginPage from './pages/LoginPage'
import RegisterPage from './pages/RegisterPage'
import MfaPage from './pages/MfaPage'
import MyBookingsPage from './pages/MyBookingsPage'
import AdminPage from './pages/AdminPage'

function ProtectedRoute({ children, adminOnly = false }) {
  const { user, ready } = useAuth()
  if (!ready) return null
  if (!user) return <Navigate to="/login" replace />
  if (adminOnly && user.role === 'PASSENGER') return <Navigate to="/" replace />
  return children
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <ToastProvider>
          <Routes>
            <Route path="/" element={<Layout />}>
              <Route index element={<HomePage />} />
              <Route path="seats"        element={<SeatsPage />} />
              <Route path="book"         element={<BookingPage />} />
              <Route path="confirmation" element={<ConfirmationPage />} />
              <Route path="login"        element={<LoginPage />} />
              <Route path="register"     element={<RegisterPage />} />
              <Route path="mfa"          element={<MfaPage />} />
              <Route path="my-bookings"
                element={<ProtectedRoute><MyBookingsPage /></ProtectedRoute>} />
              <Route path="admin"
                element={<ProtectedRoute adminOnly><AdminPage /></ProtectedRoute>} />
            </Route>
          </Routes>
        </ToastProvider>
      </AuthProvider>
    </BrowserRouter>
  )
}
