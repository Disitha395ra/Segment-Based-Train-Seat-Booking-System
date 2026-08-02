import { Outlet, NavLink, useNavigate } from 'react-router-dom'
import { useAuth } from '../../context/AuthContext'
import styles from './Layout.module.css'

export default function Layout() {
  const { user, logout, isAdmin } = useAuth()
  const navigate = useNavigate()

  const handleLogout = async () => {
    await logout()
    navigate('/login')
  }

  return (
    <div className={styles.root}>
      <nav className={styles.nav}>
        <div className={styles.navInner}>
          <NavLink to="/" className={styles.brand}>
            <span className={styles.brandTitle}>Sri Lanka Railways</span>
            <span className={styles.brandSubtitle}>Colombo Fort · Badulla</span>
          </NavLink>

          <div className={styles.navLinks}>
            <NavLink
              to="/"
              end
              className={({ isActive }) =>
                `${styles.navLink} ${isActive ? styles.navLinkActive : ''}`
              }
            >
              Book
            </NavLink>

            {user && (
              <NavLink
                to="/my-bookings"
                className={({ isActive }) =>
                  `${styles.navLink} ${isActive ? styles.navLinkActive : ''}`
                }
              >
                My Bookings
              </NavLink>
            )}

            {isAdmin && (
              <NavLink
                to="/admin"
                className={({ isActive }) =>
                  `${styles.navLink} ${styles.navLinkAdmin} ${isActive ? styles.navLinkActive : ''}`
                }
              >
                Admin
              </NavLink>
            )}

            {user ? (
              <>
                <span className={styles.navLink} style={{ cursor: 'default', opacity: 0.6 }}>
                  {user.fullName?.split(' ')[0]}
                </span>
                <button className={`${styles.authBtn} ${styles.logoutBtn}`} onClick={handleLogout}>
                  Sign out
                </button>
              </>
            ) : (
              <NavLink to="/login">
                <button className={`${styles.authBtn} ${styles.loginBtn}`}>Sign in</button>
              </NavLink>
            )}
          </div>
        </div>
      </nav>

      <main className={styles.main}>
        <Outlet />
      </main>

      <footer className={styles.footer}>
        <div className={styles.footerInner}>
          <div className={styles.footerLeft}>
            <div>Sri Lanka Railways — Segment Booking System</div>
            <div className={styles.footerRoute}>Colombo Fort → Badulla · 292 km · 22 Stations</div>
          </div>
          <div className={styles.footerRight}>
            <div>Podi Menike departs 05:55 daily</div>
            <div>Reserved seat — any segment</div>
          </div>
        </div>
      </footer>
    </div>
  )
}
