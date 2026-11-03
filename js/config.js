// Public configuration. The anon/publishable key is safe to ship: every write
// goes through a database function that checks the session phase, and the
// reveal table has no anonymous read policy.
window.EDTECH_CONFIG = {
  supabaseUrl: "https://oghwdaykvxkenpwbtwad.supabase.co",
  supabaseKey: "sb_publishable_Ovzk5yjuMHvxUiEJcHnYLg_TNtDf71b",
  siteUrl: "https://steffenerickson.github.io/edtech-evidence-lab/",
  pollMs: 4000,
};
