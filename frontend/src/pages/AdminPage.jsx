import { useState, useEffect } from 'react'
import { adminApi } from '../api/endpoints'
import { useToast } from '../components/common/Toast/ToastContext'
import styles from './AdminPage.module.css'

const today = () => new Date().toISOString().split('T')[0]
const fourWeeksAgo = () => {
  const d = new Date()
  d.setDate(d.getDate() - 28)
  return d.toISOString().split('T')[0]
}

export default function AdminPage() {
  const toast    = useToast()
  const [tab,    setTab]    = useState('occupancy')
  const [date,   setDate]   = useState(today())
  const [from,   setFrom]   = useState(fourWeeksAgo())
  const [to,     setTo]     = useState(today())
  const [data,   setData]   = useState([])
  const [audit,  setAudit]  = useState([])
  const [loading, setLoading] = useState(false)

  const loadOccupancy = async () => {
    setLoading(true)
    try {
      const res = await adminApi.occupancy(date)
      setData(res.data)
    } catch (err) {
      toast(err.message || 'Failed to load occupancy', 'error')
    } finally { setLoading(false) }
  }

  const loadRevenue = async () => {
    setLoading(true)
    try {
      const res = await adminApi.revenue(from, to)
      setData(res.data)
    } catch (err) {
      toast(err.message || 'Failed to load revenue', 'error')
    } finally { setLoading(false) }
  }

  const loadAudit = async () => {
    setLoading(true)
    try {
      const res = await adminApi.audit()
      setAudit(res.data)
    } catch (err) {
      toast(err.message || 'Failed to load audit logs', 'error')
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (tab === 'occupancy') loadOccupancy()
    else if (tab === 'revenue') loadRevenue()
    else if (tab === 'audit') loadAudit()
  }, [tab])

  return (
    <div className={styles.page}>
      <div className="container">
        <div className="page-header">
          <h1 className="page-header__title">Admin dashboard</h1>
          <p className="page-header__subtitle">Occupancy, revenue, and audit logs</p>
        </div>

        <div className={styles.tabs}>
          {['occupancy', 'revenue', 'audit'].map((t) => (
            <button
              key={t}
              className={`${styles.tab} ${tab === t ? styles.tabActive : ''}`}
              onClick={() => setTab(t)}
            >
              {t.charAt(0).toUpperCase() + t.slice(1)}
            </button>
          ))}
        </div>

        {/* ── Occupancy ──────────────────────────────────────────────────── */}
        {tab === 'occupancy' && (
          <div className={styles.section}>
            <div className={styles.controls}>
              <label>Date: <input type="date" value={date} onChange={(e) => setDate(e.target.value)}
                className={styles.dateInput} /></label>
              <button className={styles.loadBtn} onClick={loadOccupancy} disabled={loading}>
                {loading ? 'Loading…' : 'Load'}
              </button>
            </div>
            {!loading && data.length > 0 && (
              <div className={styles.tableWrap}>
                <table className="table">
                  <thead>
                    <tr>
                      <th>Coach</th><th>Class</th><th>Seat</th>
                      <th>From</th><th>To</th><th>Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.map((r, i) => (
                      <tr key={i}>
                        <td>{r.coachNumber}</td>
                        <td>{r.coachClass}</td>
                        <td>{r.seatNumber}</td>
                        <td>{r.fromStationCode}</td>
                        <td>{r.toStationCode}</td>
                        <td><span className={`badge badge--${r.status === 'CONFIRMED' ? 'success' : 'warning'}`}>{r.status}</span></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            {!loading && data.length === 0 && <p className={styles.empty}>No bookings for this date.</p>}
          </div>
        )}

        {/* ── Revenue ────────────────────────────────────────────────────── */}
        {tab === 'revenue' && (
          <div className={styles.section}>
            <div className={styles.controls}>
              <label>From: <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className={styles.dateInput} /></label>
              <label>To: <input type="date" value={to}   onChange={(e) => setTo(e.target.value)}   className={styles.dateInput} /></label>
              <button className={styles.loadBtn} onClick={loadRevenue} disabled={loading}>
                {loading ? 'Loading…' : 'Load'}
              </button>
            </div>
            {!loading && data.length > 0 && (
              <div className={styles.tableWrap}>
                <table className="table">
                  <thead>
                    <tr><th>Date</th><th>Class</th><th>Bookings</th><th>Revenue (LKR)</th></tr>
                  </thead>
                  <tbody>
                    {data.map((r, i) => (
                      <tr key={i}>
                        <td>{r.travelDate}</td>
                        <td>{r.coachClass.replace('_', ' ')}</td>
                        <td>{r.totalBookings}</td>
                        <td><strong>{Number(r.totalRevenue).toFixed(2)}</strong></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            {!loading && data.length === 0 && <p className={styles.empty}>No confirmed bookings in this range.</p>}
          </div>
        )}

        {/* ── Audit Logs ─────────────────────────────────────────────────── */}
        {tab === 'audit' && (
          <div className={styles.section}>
            <div className={styles.controls}>
              <button className={styles.loadBtn} onClick={loadAudit} disabled={loading}>
                {loading ? 'Loading…' : 'Refresh'}
              </button>
            </div>
            {!loading && audit.length > 0 && (
              <div className={styles.tableWrap}>
                <table className="table">
                  <thead>
                    <tr><th>Time</th><th>Actor</th><th>Action</th><th>Entity</th><th>IP</th></tr>
                  </thead>
                  <tbody>
                    {audit.map((r) => (
                      <tr key={r.id}>
                        <td>{new Date(r.createdAt).toLocaleString()}</td>
                        <td style={{ fontFamily: 'monospace', fontSize: '0.7rem' }}>{r.actorId?.substring(0, 8) ?? '-'}</td>
                        <td><span className="badge badge--info">{r.action}</span></td>
                        <td>{r.entityType ?? '-'}</td>
                        <td>{r.ipAddress ?? '-'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            {!loading && audit.length === 0 && <p className={styles.empty}>No audit logs.</p>}
          </div>
        )}
      </div>
    </div>
  )
}
