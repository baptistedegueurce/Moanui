import { useMemo } from 'react';
import { MantineProvider, Center, Loader } from '@mantine/core';
import { Notifications } from '@mantine/notifications';
import { Navigate, Route, Routes } from 'react-router-dom';
import { useAuth } from './lib/auth';
import { cssVars, mantineTheme, NEUTRAL } from './lib/theme';
import Shell from './components/Shell';
import SetupPage from './pages/SetupPage';
import LoginPage from './pages/LoginPage';
import HomePage from './pages/HomePage';
import DatasetsPage from './pages/DatasetsPage';
import DatasetPage from './pages/DatasetPage';
import ChartsPage from './pages/ChartsPage';
import AdminPage from './pages/AdminPage';
import StructurePage from './pages/StructurePage';
import GuidePage from './pages/GuidePage';
import SoonPage from './pages/SoonPage';
import StatsPage from './pages/StatsPage';

export default function App() {
  const { me, loading, needsSetup, structure } = useAuth();
  const theme = structure?.theme || NEUTRAL;
  const mtheme = useMemo(() => mantineTheme(theme), [theme]);

  let content;
  if (loading) {
    content = (
      <Center h="100vh">
        <Loader />
      </Center>
    );
  } else if (needsSetup) {
    content = (
      <Routes>
        <Route path="*" element={<SetupPage />} />
      </Routes>
    );
  } else if (!me) {
    content = (
      <Routes>
        <Route path="*" element={<LoginPage />} />
      </Routes>
    );
  } else {
    content = (
      <Shell>
        <Routes>
          <Route path="/" element={<HomePage />} />
          <Route path="/donnees" element={<DatasetsPage />} />
          <Route path="/donnees/:id" element={<DatasetPage />} />
          <Route path="/graphiques" element={<ChartsPage />} />
          <Route path="/cartographie" element={<SoonPage title="Cartographie" />} />
          <Route path="/statistiques" element={<StatsPage />} />
          <Route path="/guide" element={<GuidePage />} />
          <Route path="/structure" element={<StructurePage />} />
          <Route path="/administration" element={<AdminPage />} />
          <Route path="*" element={<Navigate to="/" />} />
        </Routes>
      </Shell>
    );
  }

  return (
    <MantineProvider theme={mtheme}>
      <Notifications position="top-right" />
      <div style={{ ...cssVars(theme), height: '100%' } as React.CSSProperties}>{content}</div>
    </MantineProvider>
  );
}
