'use client'

import { useMemo } from 'react'
import { AreaChart, Area, BarChart, Bar, LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts'

/**
 * Advanced Analytics Dashboard Component
 *
 * Displays multi-dimensional performance analysis:
 * - Performance trends over time
 * - Subject-wise comparison
 * - Grade-level analysis
 * - Assessment progress tracking
 */

export default function AnalyticsDashboard() {
  // Sample analytics data - Replace with real data from API
  const performanceTrendData = useMemo(() => [
    { month: 'August', avg: 72, max: 95, min: 45 },
    { month: 'September', avg: 75, max: 97, min: 48 },
    { month: 'October', avg: 78, max: 98, min: 52 },
    { month: 'November', avg: 81, max: 99, min: 55 },
    { month: 'December', avg: 79, max: 97, min: 53 },
    { month: 'January', avg: 82, max: 100, min: 58 },
  ], [])

  const subjectAnalysisData = useMemo(() => [
    { subject: 'English', score: 78, students: 245 },
    { subject: 'Mathematics', score: 82, students: 245 },
    { subject: 'Science', score: 75, students: 245 },
    { subject: 'Social Studies', score: 80, students: 245 },
    { subject: 'Hindi', score: 76, students: 245 },
  ], [])

  const gradeDistributionData = useMemo(() => [
    { name: 'Excellent (90-100)', value: 28, fill: 'hsl(160 84% 35%)' },
    { name: 'Good (80-89)', value: 38, fill: 'hsl(38 92% 50%)' },
    { name: 'Average (70-79)', value: 22, fill: 'hsl(32 93% 44%)' },
    { name: 'Below Avg (< 70)', value: 12, fill: 'hsl(0 91% 46%)' },
  ], [])

  const assessmentProgressData = useMemo(() => [
    { week: 'Week 1', completed: 45, inProgress: 12, pending: 8 },
    { week: 'Week 2', completed: 52, inProgress: 10, pending: 6 },
    { week: 'Week 3', completed: 58, inProgress: 8, pending: 4 },
    { week: 'Week 4', completed: 64, inProgress: 6, pending: 2 },
  ], [])

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '2rem' }}>
      {/* Section Header */}
      <div>
        <h2 style={{ fontSize: '1.5rem', fontWeight: 700, color: 'hsl(171 42% 32%)', marginBottom: '0.5rem' }}>
          📊 Advanced Analytics
        </h2>
        <p style={{ fontSize: '0.9rem', color: 'hsl(215 13% 27%)', maxWidth: '600px' }}>
          Comprehensive performance analysis across schools, grades, and subjects. Use these insights to identify trends and optimize educational outcomes.
        </p>
      </div>

      {/* Key Metrics Row */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '1.5rem' }}>
        <MetricCard
          label="Average Score"
          value="78.5%"
          change="+2.3%"
          color="hsl(171 42% 32%)"
          icon="📈"
        />
        <MetricCard
          label="Students Assessed"
          value="1,245"
          change="+125"
          color="hsl(38 92% 50%)"
          icon="👥"
        />
        <MetricCard
          label="Assessments Completed"
          value="64"
          change="+8"
          color="hsl(160 84% 35%)"
          icon="✓"
        />
        <MetricCard
          label="Performance Improvement"
          value="3.2 pts"
          change="→ Steady growth"
          color="hsl(32 93% 44%)"
          icon="📊"
        />
      </div>

      {/* Charts Grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(500px, 1fr))', gap: '1.5rem' }}>
        {/* Performance Trend Chart */}
        <div style={{ background: 'white', padding: '1.5rem', borderRadius: '0.75rem', boxShadow: '0 2px 8px rgba(0,0,0,0.08)', border: '1px solid hsl(220 13% 91%)' }}>
          <h3 style={{ fontSize: '1rem', fontWeight: 600, marginBottom: '1rem', color: 'hsl(217 33% 17%)' }}>
            Performance Trend (6 months)
          </h3>
          <ResponsiveContainer width="100%" height={300}>
            <AreaChart data={performanceTrendData} margin={{ top: 10, right: 30, left: 0, bottom: 0 }}>
              <defs>
                <linearGradient id="colorAvg" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="hsl(171 42% 32%)" stopOpacity={0.3}/>
                  <stop offset="95%" stopColor="hsl(171 42% 32%)" stopOpacity={0}/>
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="hsl(220 13% 91%)" />
              <XAxis dataKey="month" stroke="hsl(215 13% 27%)" style={{ fontSize: '0.75rem' }} />
              <YAxis stroke="hsl(215 13% 27%)" style={{ fontSize: '0.75rem' }} domain={[0, 100]} />
              <Tooltip
                contentStyle={{ background: 'white', border: '1px solid hsl(220 13% 91%)', borderRadius: '0.5rem' }}
                formatter={(value) => `${value}%`}
              />
              <Legend wrapperStyle={{ fontSize: '0.875rem' }} />
              <Area type="monotone" dataKey="avg" stroke="hsl(171 42% 32%)" fillOpacity={1} fill="url(#colorAvg)" name="Average Score" />
              <Area type="monotone" dataKey="max" stroke="hsl(160 84% 35%)" fill="none" strokeDasharray="5 5" name="Max Score" />
              <Area type="monotone" dataKey="min" stroke="hsl(0 91% 46%)" fill="none" strokeDasharray="5 5" name="Min Score" />
            </AreaChart>
          </ResponsiveContainer>
        </div>

        {/* Subject Analysis Chart */}
        <div style={{ background: 'white', padding: '1.5rem', borderRadius: '0.75rem', boxShadow: '0 2px 8px rgba(0,0,0,0.08)', border: '1px solid hsl(220 13% 91%)' }}>
          <h3 style={{ fontSize: '1rem', fontWeight: 600, marginBottom: '1rem', color: 'hsl(217 33% 17%)' }}>
            Subject-Wise Performance
          </h3>
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={subjectAnalysisData} margin={{ top: 10, right: 30, left: 0, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="hsl(220 13% 91%)" />
              <XAxis dataKey="subject" stroke="hsl(215 13% 27%)" style={{ fontSize: '0.75rem' }} />
              <YAxis stroke="hsl(215 13% 27%)" style={{ fontSize: '0.75rem' }} domain={[0, 100]} />
              <Tooltip
                contentStyle={{ background: 'white', border: '1px solid hsl(220 13% 91%)', borderRadius: '0.5rem' }}
                formatter={(value) => `${value}%`}
              />
              <Legend wrapperStyle={{ fontSize: '0.875rem' }} />
              <Bar dataKey="score" fill="hsl(171 42% 32%)" radius={[8, 8, 0, 0]} name="Avg Score" />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Second Row Charts */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(500px, 1fr))', gap: '1.5rem' }}>
        {/* Grade Distribution */}
        <div style={{ background: 'white', padding: '1.5rem', borderRadius: '0.75rem', boxShadow: '0 2px 8px rgba(0,0,0,0.08)', border: '1px solid hsl(220 13% 91%)' }}>
          <h3 style={{ fontSize: '1rem', fontWeight: 600, marginBottom: '1rem', color: 'hsl(217 33% 17%)' }}>
            Grade Distribution
          </h3>
          <ResponsiveContainer width="100%" height={300}>
            <PieChart>
              <Pie
                data={gradeDistributionData}
                cx="50%"
                cy="50%"
                labelLine={false}
                label={({ name, value }) => `${name.split(' ')[0]}: ${value}%`}
                outerRadius={80}
                fill="#8884d8"
                dataKey="value"
              >
                {gradeDistributionData.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={entry.fill} />
                ))}
              </Pie>
              <Tooltip formatter={(value) => `${value}%`} />
            </PieChart>
          </ResponsiveContainer>
        </div>

        {/* Assessment Progress */}
        <div style={{ background: 'white', padding: '1.5rem', borderRadius: '0.75rem', boxShadow: '0 2px 8px rgba(0,0,0,0.08)', border: '1px solid hsl(220 13% 91%)' }}>
          <h3 style={{ fontSize: '1rem', fontWeight: 600, marginBottom: '1rem', color: 'hsl(217 33% 17%)' }}>
            Assessment Progress (4 weeks)
          </h3>
          <ResponsiveContainer width="100%" height={300}>
            <LineChart data={assessmentProgressData} margin={{ top: 10, right: 30, left: 0, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="hsl(220 13% 91%)" />
              <XAxis dataKey="week" stroke="hsl(215 13% 27%)" style={{ fontSize: '0.75rem' }} />
              <YAxis stroke="hsl(215 13% 27%)" style={{ fontSize: '0.75rem' }} />
              <Tooltip
                contentStyle={{ background: 'white', border: '1px solid hsl(220 13% 91%)', borderRadius: '0.5rem' }}
              />
              <Legend wrapperStyle={{ fontSize: '0.875rem' }} />
              <Line type="monotone" dataKey="completed" stroke="hsl(160 84% 35%)" strokeWidth={2} name="Completed" dot={{ fill: 'hsl(160 84% 35%)', r: 4 }} />
              <Line type="monotone" dataKey="inProgress" stroke="hsl(38 92% 50%)" strokeWidth={2} name="In Progress" dot={{ fill: 'hsl(38 92% 50%)', r: 4 }} />
              <Line type="monotone" dataKey="pending" stroke="hsl(0 91% 46%)" strokeWidth={2} name="Pending" dot={{ fill: 'hsl(0 91% 46%)', r: 4 }} />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Insights Section */}
      <div style={{ background: 'hsl(159 41% 96%)', border: '1px solid hsl(159 39% 72%)', borderRadius: '0.75rem', padding: '1.5rem' }}>
        <h3 style={{ fontSize: '1rem', fontWeight: 600, marginBottom: '1rem', color: 'hsl(171 42% 32%)' }}>
          📌 Key Insights
        </h3>
        <ul style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem', listStyle: 'none' }}>
          <li style={{ fontSize: '0.875rem', color: 'hsl(217 33% 17%)', display: 'flex', gap: '0.75rem' }}>
            <span style={{ color: 'hsl(160 84% 35%)', fontWeight: 700 }}>✓</span>
            Performance has improved by 3.2 points over the past 6 months
          </li>
          <li style={{ fontSize: '0.875rem', color: 'hsl(217 33% 17%)', display: 'flex', gap: '0.75rem' }}>
            <span style={{ color: 'hsl(160 84% 35%)', fontWeight: 700 }}>✓</span>
            Mathematics shows the highest average score at 82%, followed by Social Studies at 80%
          </li>
          <li style={{ fontSize: '0.875rem', color: 'hsl(217 33% 17%)', display: 'flex', gap: '0.75rem' }}>
            <span style={{ color: 'hsl(160 84% 35%)', fontWeight: 700 }}>✓</span>
            28% of students are in the "Excellent" range (90-100%), indicating strong overall performance
          </li>
          <li style={{ fontSize: '0.875rem', color: 'hsl(217 33% 17%)', display: 'flex', gap: '0.75rem' }}>
            <span style={{ color: 'hsl(160 84% 35%)', fontWeight: 700 }}>✓</span>
            Assessment completion rate has increased to 64% in Week 4, up from 45% in Week 1
          </li>
        </ul>
      </div>
    </div>
  )
}

/**
 * Metric Card Component
 */
function MetricCard({
  label,
  value,
  change,
  color,
  icon,
}: {
  label: string
  value: string | number
  change: string
  color: string
  icon: string
}) {
  return (
    <div style={{
      background: 'white',
      border: `1px solid hsl(220 13% 91%)`,
      borderRadius: '0.75rem',
      padding: '1.5rem',
      boxShadow: '0 2px 8px rgba(0,0,0,0.08)',
      transition: 'transform 0.2s ease, box-shadow 0.2s ease',
    }}
    onMouseEnter={(e) => {
      e.currentTarget.style.transform = 'translateY(-2px)'
      e.currentTarget.style.boxShadow = '0 8px 16px rgba(0,0,0,0.12)'
    }}
    onMouseLeave={(e) => {
      e.currentTarget.style.transform = 'translateY(0)'
      e.currentTarget.style.boxShadow = '0 2px 8px rgba(0,0,0,0.08)'
    }}
    >
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '1rem' }}>
        <div style={{ fontSize: '2rem' }}>{icon}</div>
        <span style={{
          background: `${color}15`,
          color: color,
          padding: '0.25rem 0.75rem',
          borderRadius: '9999px',
          fontSize: '0.75rem',
          fontWeight: 600,
        }}>
          {change}
        </span>
      </div>
      <div style={{ fontSize: '0.875rem', color: 'hsl(215 13% 27%)', marginBottom: '0.5rem' }}>
        {label}
      </div>
      <div style={{ fontSize: '1.875rem', fontWeight: 700, color: 'hsl(217 33% 17%)' }}>
        {value}
      </div>
    </div>
  )
}
