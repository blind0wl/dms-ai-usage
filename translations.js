.pragma library

var strings = {
    "Claude Code Usage":
        { fr: "Utilisation Claude Code" },
    "Subscription":
        { fr: "Abonnement" },
    "5h Rate Window":
        { fr: "Fenêtre 5h" },
    "used":
        { fr: "utilisé" },
    "Resets in":
        { fr: "Réinitialise dans" },
    "Resetting...":
        { fr: "Réinitialisation..." },
    "7-Day Usage":
        { fr: "Utilisation 7 jours" },
    "sessions":
        { fr: "sessions" },
    "msgs":
        { fr: "msgs" },
    "Daily Activity":
        { fr: "Activité quotidienne" },
    "Token Consumption":
        { fr: "Consommation de tokens" },
    "Today":
        { fr: "Aujourd'hui" },
    "Week":
        { fr: "Semaine" },
    "Month":
        { fr: "Mois" },
    "Models This Week":
        { fr: "Modèles cette semaine" },
    "Since":
        { fr: "Depuis" },
    // Settings
    "Monitor your Claude Code subscription usage. Rate limits and subscription tier are detected automatically via the Anthropic API.":
        { fr: "Surveillez l'utilisation de votre abonnement Claude Code. Les limites et le type d'abonnement sont détectés automatiquement via l'API Anthropic." },
    "Refresh Interval":
        { fr: "Intervalle de rafraîchissement" },
    "How often to fetch usage data (minutes)":
        { fr: "Fréquence de mise à jour des données (minutes)" },
    "All":
        { fr: "Tout" },
    "Profile":
        { fr: "Profil" },
    "total":
        { fr: "total" },
    // Pacing
    "over pace":
        { fr: "au-dessus du rythme" },
    "under pace":
        { fr: "en dessous du rythme" },
    "On pace":
        { fr: "Dans les temps" },
    "Over quota":
        { fr: "Quota dépassé" },
    "Show pacing":
        { fr: "Afficher le rythme" },
    "Show whether usage is ahead of or behind the time window":
        { fr: "Indique si l'utilisation est en avance ou en retard sur la fenêtre de temps" },
    "Custom Profiles":
        { fr: "Profils personnalisés" },
    "Name":
        { fr: "Nom" },
    "Config directory":
        { fr: "Dossier de configuration" },
    "Track extra Claude config directories. Point at a CLAUDE_CONFIG_DIR (the folder containing projects/). ~/.claude, Claude Code Switcher and claude-code-profiles are detected automatically.":
        { fr: "Suivre d'autres dossiers de configuration Claude. Indiquez un CLAUDE_CONFIG_DIR (le dossier contenant projects/). ~/.claude, Claude Code Switcher et claude-code-profiles sont détectés automatiquement." },
}

function tr(key, lang) {
    if (!lang || lang === "en" || !strings[key] || !strings[key][lang])
        return key
    return strings[key][lang]
}
