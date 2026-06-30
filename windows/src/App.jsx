import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { useEffect, useState } from 'react';

const COLORS = {
    running: '#34C759',
    waiting_input: '#FF9F0A',
    stopped: '#FF453A',
    idle: '#8E8E93',
};
const LABEL = {
    running: 'Running',
    waiting_input: 'Waiting for input',
    stopped: 'Stopped',
    idle: 'Idle',
};
const CHIP = { running: 'RUN', waiting_input: 'WAIT', stopped: 'STOP', idle: 'IDLE' };

export default function App() {
    const [data, setData] = useState({ overall: 'idle', sessions: [] });

    useEffect(() => {
        const refresh = () => invoke('get_status').then(setData).catch(() => {});
        refresh();
        const id = setInterval(refresh, 4000);
        const unlisten = listen('status-updated', (e) => setData(e.payload));
        return () => {
            clearInterval(id);
            unlisten.then((u) => u());
        };
    }, []);

    const color = COLORS[data.overall] ?? COLORS.idle;

    return (
        <div className="panel">
            <header className="header">
                <span className="brand-dot" />
                <span className="brand">Lubby</span>
                <span className="tab active">Sessions</span>
            </header>

            <div className="hero">
                <span
                    className="badge"
                    style={{ background: `${color}26`, boxShadow: `0 0 18px ${color}55` }}
                >
                    <span className="dot lg" style={{ background: color }} />
                </span>
                <div className="hero-title">{LABEL[data.overall] ?? 'Idle'}</div>
                <div className="hero-sub">
                    {data.sessions.length} {data.sessions.length === 1 ? 'session' : 'sessions'}
                </div>
            </div>

            <div className="rows">
                {data.sessions.length === 0 && (
                    <div className="empty">No active Claude sessions</div>
                )}
                {data.sessions.map((s) => {
                    const c = COLORS[s.status] ?? COLORS.idle;
                    return (
                        <div className="row" key={s.id}>
                            <span className="dot" style={{ background: c }} />
                            <span className="name">{s.project || s.agent}</span>
                            <span className="chip" style={{ color: c, background: `${c}26` }}>
                                {CHIP[s.status] ?? 'IDLE'}
                            </span>
                        </div>
                    );
                })}
            </div>
        </div>
    );
}
