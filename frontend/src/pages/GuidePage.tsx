// Guide des bonnes pratiques : un document de référence, structuré comme un mémo méthodologique,
// avec ses sources. Les références viennent du serveur (même base que les fiches méthode).
import { ReactNode, useEffect, useMemo, useRef, useState } from 'react';
import { Text, Title } from '@mantine/core';
import { useAuth } from '../lib/auth';

interface Section {
  id: string;
  title: string;
  body: ReactNode;
  refs: string[];
}

function Table({ head, rows }: { head: string[]; rows: ReactNode[][] }) {
  return (
    <table className="mo-doc-table">
      <thead>
        <tr>
          {head.map((h) => (
            <th key={h}>{h}</th>
          ))}
        </tr>
      </thead>
      <tbody>
        {rows.map((r, i) => (
          <tr key={i}>
            {r.map((c, j) => (
              <td key={j}>{c}</td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

export default function GuidePage() {
  const { meta } = useAuth();
  const bib = meta?.biblio || {};
  const c = (...keys: string[]) => {
    const parts = keys.map((k) => bib[k]?.court).filter(Boolean);
    return parts.length ? <span className="mo-cite"> ({parts.join(' ; ')})</span> : null;
  };

  const sections: Section[] = [
    {
      id: 'principes',
      title: 'Principes : la donnée source ne change jamais',
      refs: ['wilkinson2016', 'broman2018'],
      body: (
        <>
          <p>
            Un résultat n’est vérifiable que si l’on peut retrouver la donnée d’origine et refaire chaque traitement. Les principes FAIR insistent sur la provenance et
            la réutilisation des données{c('wilkinson2016')} ; les recommandations pour les tableurs commencent par ne jamais modifier la saisie d’origine et
            documenter toute correction{c('broman2018')}.
          </p>
          <h4>Dans Moanui</h4>
          <ul>
            <li>À l’import, le fichier est copié tel quel, en lecture seule, avec son empreinte SHA-256 ; « Vérifier l’intégrité » confirme qu’il n’a pas bougé.</li>
            <li>Chaque opération (filtre, correction, calcul) est une étape de l’historique : auteur, date, justification, nombre de lignes avant et après.</li>
            <li>Une étape peut être désactivée, modifiée, déplacée ou supprimée ; l’aperçu « à cette étape » montre la donnée à n’importe quel moment du traitement.</li>
            <li>La fiche méthode jointe à chaque export reprend la source, les opérations dans l’ordre et la requête SQL qui refait tout.</li>
          </ul>
        </>
      ),
    },
    {
      id: 'organiser',
      title: 'Organiser et contrôler avant d’analyser',
      refs: ['wickham2014', 'zuur2010', 'tukey1977', 'little2019'],
      body: (
        <>
          <p>
            Une table exploitable a une ligne par observation et une colonne par variable, avec un type cohérent dans chaque colonne{c('wickham2014')}. L’exploration
            préalable (valeurs extrêmes, manques, colinéarité, dépendance entre observations) évite la plupart des erreurs d’analyse{c('zuur2010')}.
          </p>
          <Table
            head={['Point à vérifier', 'Pourquoi', 'Où dans Moanui']}
            rows={[
              ['Types de colonnes', 'Un code « 01 » lu comme nombre perd son zéro ; une date lue comme texte ne se trie pas.', 'Liste des colonnes (abc, 123, date), « Changer le type »'],
              ['Doublons', 'Une déclaration en double gonfle les sommes sans changer les moyennes.', 'Lignes, « Supprimer les doublons »'],
              ['Valeurs manquantes', 'Les remplacer par une moyenne réduit la variabilité et peut biaiser les tests.', 'Contrôle qualité ; « Remplir les vides » à justifier'],
              [
                'Valeurs extrêmes',
                'Au-delà de 1,5 à 3 écarts interquartiles, vérifier saisie et unité (kg ou tonnes) avant de retirer quoi que ce soit.',
                'Contrôle qualité, boîtes à moustaches',
              ],
              ['Codes et libellés', 'Un même code écrit « otb », « OTB » ou « OTB  » compte pour trois.', 'Colonnes, « Transformer » (majuscules, espaces)'],
            ]}
          />
          <p>
            Les manques ne sont pas neutres : s’ils dépendent de la valeur manquante (petits navires sans déclaration, par exemple), aucune imputation simple ne corrige
            le biais{c('little2019')}. Les valeurs extrêmes se repèrent visuellement (boîtes à moustaches){c('tukey1977')} ; une valeur extrême n’est pas une erreur
            tant qu’elle n’est pas expliquée.
          </p>
        </>
      ),
    },
    {
      id: 'halieutique',
      title: 'Données halieutiques : SACROIS, engins, métiers',
      refs: ['sih_sacrois', 'sih_sacrois_data', 'isscfg', 'dcf_metiers'],
      body: (
        <>
          <p>
            SACROIS croise les journaux de bord, les fiches de pêche, les ventes, la VMS et le calendrier d’activité pour produire, par navire et par marée ou par jour,
            une donnée de production et d’effort qualifiée ; l’algorithme ne corrige pas les déclarations, il choisit la meilleure source et indique la qualité du
            croisement{c('sih_sacrois', 'sih_sacrois_data')}.
          </p>
          <ul>
            <li>
              Les engins suivent la classification FAO ISSCFG (OTB chalut de fond à panneaux, GNS filet maillant calé, FPO casier…){c('isscfg')}. La cohérence engin /
              espèce de Moanui s’appuie sur cette liste complète ; un engin improbable est signalé et un engin suggéré proposé, sans écraser la déclaration.
            </li>
            <li>Les métiers (engin × espèces cibles × maillage) suivent les niveaux de la collecte de données européenne (DCF){c('dcf_metiers')}.</li>
            <li>Toujours vérifier l’unité (kg, tonnes, euros) avant d’empiler des fichiers de sources différentes.</li>
            <li>Compter les navires avec leur identifiant (numéro CFR ou immatriculation), jamais avec leur nom.</li>
          </ul>
        </>
      ),
    },
    {
      id: 'vms',
      title: 'VMS et cartographie',
      refs: ['lee2010', 'hintzen2012', 'gerritsen2011', 'ices_rect', 'brewer2003', 'monmonier2018', 'shom_delmar', 'ofb_amp'],
      body: (
        <>
          <p>
            Les positions VMS indiquent où se trouve un navire, pas ce qu’il fait. L’activité de pêche se déduit le plus souvent de la vitesse, avec des seuils propres à
            chaque engin, après retrait des doublons et des positions au port{c('lee2010', 'hintzen2012')}. Les captures déclarées par navire et par jour peuvent ensuite
            être réparties sur les positions de pêche du même jour{c('gerritsen2011')}.
          </p>
          <Table
            head={['Étape', 'Point de vigilance']}
            rows={[
              ['Harmoniser (modèle « Préparation VMS »)', 'Chez CLS, la vitesse « SP » est en dixièmes de nœud ; chez Agiltech, en nœuds.'],
              ['Identifier l’activité', 'Seuils à vérifier sur quelques marées connues ; une vitesse calculée de plus de 25 nœuds signale une position erronée.'],
              ['Répartir les captures', 'Une faible part attribuée signale des identifiants différents, des navires sans VMS ou une date de débarquement au lieu de la date de pêche.'],
              ['Cartographier', 'Préférer le carroyage ou les rectangles CIEM avec secret statistique aux positions brutes pour toute diffusion.'],
            ]}
          />
          <p>
            Les rectangles statistiques CIEM (1° × 0,5°) sont l’unité spatiale des déclarations{c('ices_rect')}. Sur une carte en aplats, les bornes des classes et la
            palette changent la lecture : une palette séquentielle pour une quantité, divergente seulement autour d’une valeur de référence{c('brewer2003', 'monmonier2018')}.
            Les limites maritimes (Shom) et les aires protégées (OFB) intégrées sont des références datées, à citer{c('shom_delmar', 'ofb_amp')}.
          </p>
        </>
      ),
    },
    {
      id: 'secret',
      title: 'Secret statistique et données personnelles',
      refs: ['loi1951', 'reg223', 'rgpd'],
      body: (
        <>
          <p>
            Une statistique diffusée ne doit pas permettre d’identifier un déclarant{c('loi1951', 'reg223')}. En pratique, les agrégats comptant moins de trois navires
            sont masqués ; une case dominée par un seul navire peut aussi le trahir. Noms, immatriculations et coordonnées sont des données personnelles{c('rgpd')} :
            les traiter en interne est permis, les diffuser ne l’est pas.
          </p>
          <ul>
            <li>« Regrouper » et les cartes agrégées proposent le masquage sous un nombre minimal de navires.</li>
            <li>À l’export, Moanui signale les colonnes sensibles non anonymisées ; l’opération « Anonymiser » les remplace par des codes.</li>
            <li>Un code stable reste une pseudonymisation tant que la table de correspondance existe : la conserver à part.</li>
          </ul>
        </>
      ),
    },
    {
      id: 'tests',
      title: 'Tests statistiques : choisir et lire',
      refs: ['wasserstein2016', 'delacre2017', 'shapiro1965', 'holm1979', 'cochran1954', 'cohen1988'],
      body: (
        <>
          <p>
            Une p-value indique si un écart pourrait venir du hasard ; elle ne dit ni sa taille ni son importance{c('wasserstein2016')}. Moanui donne donc toujours la
            taille d’effet{c('cohen1988')} et, quand c’est possible, un intervalle de confiance.
          </p>
          <Table
            head={['Question', 'Test par défaut', 'Condition vérifiée', 'Si elle n’est pas remplie']}
            rows={[
              ['Deux groupes diffèrent-ils ?', <>t de Welch{c('delacre2017')}</>, <>Normalité{c('shapiro1965')} ou grand effectif</>, 'Mann-Whitney'],
              ['Plusieurs groupes diffèrent-ils ?', 'ANOVA (de Welch si variances inégales)', 'Normalité, égalité des variances', <>Kruskal-Wallis, puis paires corrigées{c('holm1979')}</>],
              ['Deux catégories sont-elles liées ?', 'χ² d’indépendance', <>Effectifs attendus ≥ 5{c('cochran1954')}</>, 'Test exact de Fisher (2 × 2) ou regroupement'],
              ['Deux mesures varient-elles ensemble ?', 'Pearson', 'Normalité, pas de valeur extrême', 'Spearman'],
              ['Quels facteurs expliquent une mesure ?', 'Régression linéaire', 'Résidus normaux, variance constante', 'GLM (section suivante)'],
            ]}
          />
          <ul>
            <li>Les observations doivent être indépendantes : plusieurs lignes d’une même marée ou d’un même navire ne le sont pas. Regrouper d’abord.</li>
            <li>Une condition bloquante peut être contournée, avec une justification écrite reprise dans la fiche.</li>
            <li>« Non significatif » ne veut pas dire « identique » : l’échantillon peut simplement être trop petit.</li>
          </ul>
        </>
      ),
    },
    {
      id: 'modeles',
      title: 'Modèles de captures (GLM) et CPUE standardisées',
      refs: ['mccullagh1989', 'venables2004', 'maunder2004', 'campbell2004', 'verhoef2007', 'martin2005', 'lo1992', 'dunn1996', 'zuur2009'],
      body: (
        <>
          <p>
            Les captures sont positives, asymétriques et souvent nulles : la régression linéaire leur convient mal. Les modèles linéaires généralisés choisissent une loi
            adaptée à la nature de la mesure{c('mccullagh1989', 'venables2004')}.
          </p>
          <Table
            head={['Mesure', 'Famille', 'Remarque']}
            rows={[
              ['Présence / absence (0 / 1)', 'Logistique', 'Effets en rapports de cotes'],
              ['Comptages (individus, marées)', 'Poisson, ou binomiale négative', <>Binomiale négative si la variance dépasse la moyenne{c('verhoef2007')}</>],
              ['Quantités positives (kg, CPUE)', 'Gamma (lien log)', 'Effets multiplicatifs'],
              ['Quantités avec beaucoup de zéros', <>Modèle delta{c('lo1992')}</>, <>Présence (logistique), puis quantité si présent (Gamma){c('martin2005')}</>],
            ]}
          />
          <p>
            Pour une CPUE, modéliser les captures avec l’effort en décalage (offset) plutôt que le rapport captures / effort ; mettre l’année en texte et en premier
            facteur donne l’indice annuel standardisé, c’est-à-dire l’évolution corrigée des changements d’engins, de zones ou de saisons{c('maunder2004', 'campbell2004')}. L’ajustement se juge sur les résidus quantiles, qui suivent une loi normale si la famille est adaptée{c('dunn1996')}. Plusieurs lignes d’un même navire
            appellent un effet aléatoire navire (modèle mixte){c('zuur2009')} ; à défaut, interpréter les p-values avec prudence.
          </p>
        </>
      ),
    },
    {
      id: 'graphiques',
      title: 'Des graphiques justes',
      refs: ['cleveland1984', 'tufte2001', 'wilke2019', 'crameri2020'],
      body: (
        <>
          <p>
            On compare bien des positions sur une échelle commune, moins bien des longueurs, mal des angles et des surfaces{c('cleveland1984')} : les barres et les points
            sont préférables aux secteurs et aux bulles. Tout élément qui ne porte pas d’information (fond, quadrillage appuyé, 3D) gêne la lecture{c('tufte2001', 'wilke2019')}.
          </p>
          <ul>
            <li>Indiquer la source, l’unité et la période ; un axe de barres commence à zéro ; une échelle logarithmique se signale.</li>
            <li>Deux axes verticaux suggèrent des liens qui n’existent pas : à éviter, ou à légender sans ambiguïté.</li>
            <li>Plusieurs petits graphiques identiques (petits multiples) valent mieux qu’un graphique surchargé.</li>
            <li>Palettes lisibles par les personnes daltoniennes ; pas d’arc-en-ciel pour une quantité{c('crameri2020')}.</li>
          </ul>
        </>
      ),
    },
  ];

  const allRefs = useMemo(() => {
    const keys = Array.from(new Set(sections.flatMap((s) => s.refs))).filter((k) => bib[k]);
    return keys.map((k) => bib[k].complet).sort((a, b) => a.localeCompare(b, 'fr'));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [bib]);

  const [active, setActive] = useState('principes');
  const box = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const el = box.current;
    if (!el) return;
    const obs = new IntersectionObserver(
      (entries) => entries.filter((e) => e.isIntersecting).forEach((e) => setActive(e.target.id)),
      { root: null, rootMargin: '0px 0px -70% 0px' },
    );
    el.querySelectorAll('section[id]').forEach((s) => obs.observe(s));
    return () => obs.disconnect();
  }, []);

  return (
    <div className="mo-doc-layout">
      <nav className="mo-doc-toc">
        <Text className="mo-section-title" mb={8}>
          Sommaire
        </Text>
        {sections.map((s, i) => (
          <a key={s.id} href={`#${s.id}`} data-active={active === s.id || undefined}>
            {i + 1}. {s.title}
          </a>
        ))}
        <a href="#references" data-active={active === 'references' || undefined}>
          Références
        </a>
      </nav>
      <article className="mo-doc" ref={box}>
        <Title order={1}>Bonnes pratiques</Title>
        <Text c="dimmed" mb="lg">
          Les règles que Moanui applique ou vérifie, et les références sur lesquelles elles reposent. Les fiches méthode citent les mêmes sources.
        </Text>
        {sections.map((s, i) => (
          <section key={s.id} id={s.id}>
            <h3>
              {i + 1}. {s.title}
            </h3>
            {s.body}
          </section>
        ))}
        <section id="references">
          <h3>Références</h3>
          <ul className="mo-doc-refs">
            {allRefs.map((r) => (
              <li key={r}>{r}</li>
            ))}
          </ul>
        </section>
      </article>
    </div>
  );
}
