import React from 'react';
import { Music2, ArrowDownUp, Image as ImageIcon, ListMusic, Sliders, ShieldCheck } from 'lucide-react';

export type NavTab = 'library' | 'transfer' | 'metadata' | 'playlists';

interface Props {
  activeTab: NavTab;
  onSelectTab: (tab: NavTab) => void;
  trackCount: number;
  transferQueueCount: number;
}

export const Sidebar: React.FC<Props> = ({
  activeTab,
  onSelectTab,
  trackCount,
  transferQueueCount,
}) => {
  const navItems: { id: NavTab; label: string; icon: React.ReactNode; badge?: string | number }[] = [
    {
      id: 'library',
      label: 'Music Library',
      icon: <Music2 className="w-4 h-4" />,
      badge: trackCount > 0 ? trackCount : undefined,
    },
    {
      id: 'transfer',
      label: 'Transfer & Convert',
      icon: <ArrowDownUp className="w-4 h-4" />,
      badge: transferQueueCount > 0 ? transferQueueCount : undefined,
    },
    {
      id: 'metadata',
      label: 'Metadata & Artwork',
      icon: <ImageIcon className="w-4 h-4" />,
    },
    {
      id: 'playlists',
      label: 'Playlists (.M3U8)',
      icon: <ListMusic className="w-4 h-4" />,
    },
  ];

  return (
    <aside className="w-64 bg-walkman-card border-r border-walkman-border flex flex-col justify-between p-4 flex-shrink-0 min-h-[calc(100vh-65px)]">
      {/* Navigation Links */}
      <nav className="space-y-1.5">
        <div className="text-[10px] font-semibold tracking-wider text-walkman-dim uppercase px-3 py-2">
          Management
        </div>
        {navItems.map((item) => {
          const isActive = activeTab === item.id;
          return (
            <button
              key={item.id}
              onClick={() => onSelectTab(item.id)}
              className={`w-full flex items-center justify-between px-3 py-2.5 rounded-lg text-xs font-medium transition-all ${
                isActive
                  ? 'bg-walkman-hover text-walkman-gold border-l-2 border-walkman-gold shadow-sm font-semibold'
                  : 'text-zinc-400 hover:text-white hover:bg-zinc-800/40'
              }`}
            >
              <div className="flex items-center space-x-3">
                <span className={isActive ? 'text-walkman-gold' : 'text-zinc-500'}>
                  {item.icon}
                </span>
                <span>{item.label}</span>
              </div>
              {item.badge !== undefined && (
                <span
                  className={`text-[10px] px-1.5 py-0.5 rounded font-mono ${
                    isActive
                      ? 'bg-amber-500/20 text-walkman-gold'
                      : 'bg-zinc-800 text-zinc-400'
                  }`}
                >
                  {item.badge}
                </span>
              )}
            </button>
          );
        })}
      </nav>

      {/* Hardware Rules Compliance Pill */}
      <div className="p-3.5 rounded-xl bg-walkman-bg border border-walkman-border space-y-2 text-[11px]">
        <div className="flex items-center space-x-1.5 text-walkman-gold font-medium">
          <ShieldCheck className="w-4 h-4 text-walkman-gold flex-shrink-0" />
          <span>NW-A55L Constraints</span>
        </div>
        <ul className="text-zinc-400 space-y-1 pl-1 text-[10px]">
          <li className="flex items-center space-x-1.5">
            <span className="w-1 h-1 rounded-full bg-amber-500"></span>
            <span>Baseline RGB JPEG (800x800)</span>
          </li>
          <li className="flex items-center space-x-1.5">
            <span className="w-1 h-1 rounded-full bg-amber-500"></span>
            <span>Strict ID3v2.3 (UTF-16)</span>
          </li>
          <li className="flex items-center space-x-1.5">
            <span className="w-1 h-1 rounded-full bg-amber-500"></span>
            <span>FAT32 Clean Paths</span>
          </li>
          <li className="flex items-center space-x-1.5">
            <span className="w-1 h-1 rounded-full bg-amber-500"></span>
            <span>CRLF .M3U8 Playlists</span>
          </li>
        </ul>
      </div>
    </aside>
  );
};
