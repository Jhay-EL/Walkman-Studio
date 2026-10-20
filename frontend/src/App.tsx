import React, { useState, useEffect } from 'react';
import { TopStorageBar } from './components/TopStorageBar';
import { Sidebar, NavTab } from './components/Sidebar';
import { LibraryView } from './components/LibraryView';
import { TransferQueueView } from './components/TransferQueueView';
import { MetadataStudioView } from './components/MetadataStudioView';
import { PlaylistsView } from './components/PlaylistsView';
import { CleanEjectModal } from './components/CleanEjectModal';
import { WalkmanDrive, Track, Playlist } from './types';
import { api } from './api';
import { RefreshCw, Usb } from 'lucide-react';

export const App: React.FC = () => {
  const [drives, setDrives] = useState<WalkmanDrive[]>([]);
  const [activeDrive, setActiveDrive] = useState<WalkmanDrive | null>(null);
  const [activeTab, setActiveTab] = useState<NavTab>('library');
  const [loadingDrives, setLoadingDrives] = useState<boolean>(true);
  const [loadingLibrary, setLoadingLibrary] = useState<boolean>(false);
  const [tracks, setTracks] = useState<Track[]>([]);
  const [playlists, setPlaylists] = useState<Playlist[]>([]);
  const [selectedTrackForEdit, setSelectedTrackForEdit] = useState<Track | null>(null);
  const [isEjectModalOpen, setIsEjectModalOpen] = useState<boolean>(false);

  // Initial load
  useEffect(() => {
    loadDrives();
  }, []);

  // Auto-poll for Walkman USB connection every 2.5 seconds when no drive is connected
  useEffect(() => {
    if (drives.length === 0) {
      const interval = setInterval(() => {
        loadDrives(false);
      }, 2500);
      return () => clearInterval(interval);
    }
  }, [drives.length]);

  // When active drive changes, reload library & playlists
  useEffect(() => {
    if (activeDrive) {
      loadLibraryAndPlaylists(activeDrive.mount_point);
    } else {
      setTracks([]);
      setPlaylists([]);
    }
  }, [activeDrive]);

  const loadDrives = async (showLoadingSpinner = true) => {
    if (showLoadingSpinner) setLoadingDrives(true);
    try {
      // allowVirtual is strictly false to only recognize physical devices
      const detected = await api.getDrives(false);
      setDrives(detected);
      if (detected.length > 0) {
        setActiveDrive((prev) => {
          if (prev && detected.some((d) => d.id === prev.id)) {
            return detected.find((d) => d.id === prev.id) || detected[0];
          }
          return detected[0];
        });
      } else {
        setActiveDrive(null);
      }
    } catch (e) {
      console.error('Error detecting drives:', e);
    } finally {
      if (showLoadingSpinner) setLoadingDrives(false);
    }
  };

  const loadLibraryAndPlaylists = async (mountPoint: string) => {
    setLoadingLibrary(true);
    try {
      const [libData, plData] = await Promise.all([
        api.getLibrary(mountPoint),
        api.getPlaylists(mountPoint),
      ]);
      setTracks(libData.tracks || []);
      setPlaylists(plData || []);
    } catch (e) {
      console.error('Error scanning library:', e);
    } finally {
      setLoadingLibrary(false);
    }
  };

  const handleEditTrack = (track: Track) => {
    setSelectedTrackForEdit(track);
    setActiveTab('metadata');
  };

  return (
    <div className="min-h-screen bg-walkman-bg text-zinc-100 flex flex-col">
      {/* Top Storage Bar */}
      <TopStorageBar
        drives={drives}
        activeDrive={activeDrive}
        onSelectDrive={(d) => setActiveDrive(d)}
        onRefresh={() => loadDrives(true)}
        onOpenEject={() => setIsEjectModalOpen(true)}
        loading={loadingDrives}
      />

      {/* Main Workspace Layout */}
      <div className="flex flex-1 overflow-hidden">
        {/* Left Sidebar */}
        <Sidebar
          activeTab={activeTab}
          onSelectTab={setActiveTab}
          trackCount={tracks.length}
          transferQueueCount={0}
        />

        {/* Dynamic Center Stage */}
        <main className="flex-1 overflow-y-auto bg-walkman-bg">
          {drives.length === 0 ? (
            /* Waiting for Real Device Screen */
            <div className="flex flex-col items-center justify-center min-h-[calc(100vh-120px)] p-8 text-center animate-in fade-in duration-300">
              <div className="relative mb-6">
                <div className="w-20 h-20 rounded-2xl bg-gradient-to-br from-amber-500/20 to-yellow-600/10 border border-amber-500/30 flex items-center justify-center shadow-2xl shadow-amber-900/20 animate-pulse">
                  <span className="text-3xl font-black text-walkman-gold tracking-tighter">W.</span>
                </div>
                <div className="absolute -bottom-1 -right-1 w-6 h-6 rounded-full bg-zinc-900 border border-zinc-700 flex items-center justify-center">
                  <Usb className="w-3.5 h-3.5 text-walkman-gold" />
                </div>
              </div>

              <h2 className="text-xl font-semibold text-white mb-2">
                Connect Sony Walkman NW-A55
              </h2>
              <p className="text-xs text-zinc-400 max-w-md mb-8">
                Plug in your Sony Walkman with the USB cable. Walkman Studio will automatically detect the internal <code className="text-amber-400 font-mono">WALKMAN</code> storage and your MicroSD card.
              </p>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-4 max-w-2xl w-full text-left mb-8">
                <div className="p-4 rounded-xl bg-walkman-card border border-walkman-border space-y-2">
                  <span className="w-6 h-6 rounded-full bg-zinc-800 text-walkman-gold text-xs font-mono font-bold flex items-center justify-center">
                    1
                  </span>
                  <h4 className="text-xs font-semibold text-white">Plug in USB Cable</h4>
                  <p className="text-[11px] text-zinc-400">
                    Connect your NW-A55 using the Sony WM-Port USB cable.
                  </p>
                </div>

                <div className="p-4 rounded-xl bg-walkman-card border border-walkman-border space-y-2">
                  <span className="w-6 h-6 rounded-full bg-zinc-800 text-walkman-gold text-xs font-mono font-bold flex items-center justify-center">
                    2
                  </span>
                  <h4 className="text-xs font-semibold text-white">Select USB Mass Storage</h4>
                  <p className="text-[11px] text-zinc-400">
                    Tap <strong className="text-zinc-200">"Connect / File Transfer"</strong> on your Walkman screen.
                  </p>
                </div>

                <div className="p-4 rounded-xl bg-walkman-card border border-walkman-border space-y-2">
                  <span className="w-6 h-6 rounded-full bg-zinc-800 text-walkman-gold text-xs font-mono font-bold flex items-center justify-center">
                    3
                  </span>
                  <h4 className="text-xs font-semibold text-white">Automatic Detection</h4>
                  <p className="text-[11px] text-zinc-400">
                    Both Internal and MicroSD drives will mount and load your music automatically.
                  </p>
                </div>
              </div>

              <div className="flex items-center space-x-2.5 text-xs text-zinc-500 font-mono bg-zinc-900/60 px-4 py-2 rounded-full border border-zinc-800">
                <RefreshCw className="w-3.5 h-3.5 animate-spin text-walkman-gold" />
                <span>Listening for physical Walkman connection...</span>
              </div>
            </div>
          ) : (
            /* Connected Device Views */
            <>
              {activeTab === 'library' && (
                <LibraryView
                  tracks={tracks}
                  loading={loadingLibrary}
                  onEditTrack={handleEditTrack}
                  onGoToTransfer={() => setActiveTab('transfer')}
                />
              )}

              {activeTab === 'transfer' && (
                <TransferQueueView
                  drives={drives}
                  activeDrive={activeDrive}
                  onTransferComplete={() => {
                    if (activeDrive) loadLibraryAndPlaylists(activeDrive.mount_point);
                  }}
                />
              )}

              {activeTab === 'metadata' && (
                <MetadataStudioView
                  selectedTrack={selectedTrackForEdit}
                  onSaved={() => {
                    if (activeDrive) loadLibraryAndPlaylists(activeDrive.mount_point);
                  }}
                />
              )}

              {activeTab === 'playlists' && (
                <PlaylistsView
                  activeDrive={activeDrive}
                  playlists={playlists}
                  libraryTracks={tracks}
                  onRefreshPlaylists={() => {
                    if (activeDrive) loadLibraryAndPlaylists(activeDrive.mount_point);
                  }}
                />
              )}
            </>
          )}
        </main>
      </div>

      {/* Clean & Safe Eject Modal */}
      <CleanEjectModal
        isOpen={isEjectModalOpen}
        onClose={() => setIsEjectModalOpen(false)}
        activeDrive={activeDrive}
        onEjected={() => {
          loadDrives(true);
        }}
      />
    </div>
  );
};
export default App;
