// ==============================================================================
// apps/Theme.HC - Sovereign semantic theme / skin engine (P4.8)
//
// Ownership of the desktop palette moved OUT of Compositor.HC (which P5 will
// dissolve). This module owns the single `g_theme` palette and the two entry
// points that mutate it (ThemeApply / ThemeSetByName); WM, DolDoc and Compositor
// all read the same global. Loaded in Stage 6 before Compositor/DolDoc/WM.
// ==============================================================================

#define THEME_MOCHA      0
#define THEME_LATTE      1
#define THEME_TOKYO      2
#define THEME_NORD       3
#define THEME_TEMPLE     4
#define THEME_CYBERPUNK  5
#define THEME_COUNT      6

// ------------------------------------------------------------------------------
// 1. Dynamic Semantic Theme & Skin Specification (Zero Hardcoded Hex at call sites)
// ------------------------------------------------------------------------------
class CThemePalette {
    I64 theme_id;
    U8  name[32];
    U32 bg_crust;
    U32 bg_mantle;
    U32 bg_base;
    U32 bg_surface0;
    U32 bg_surface1;
    U32 bg_surface2;
    U32 border_subtle;
    U32 border_active;
    U32 text_primary;
    U32 text_secondary;
    U32 text_muted;
    U32 accent_primary;
    U32 accent_secondary;
    U32 accent_tertiary;
    U32 accent_cyan;
    U32 accent_teal;
    U32 status_success;
    U32 status_warning;
    U32 status_peach;
    U32 status_danger;
    U32 glass_tint;
    U32 shadow_color;
    // Skin metrics
    I64 titlebar_h;
    I64 border_w;
    I64 corner_radius;
    I64 btn_size;
};

CThemePalette g_theme;

// ------------------------------------------------------------------------------
// 2. Runtime Theme Engine (6 Built-In Semantic Themes)
// ------------------------------------------------------------------------------
U0 ThemeApply(I64 tid) {
    if (tid < 0 || tid >= THEME_COUNT) tid = THEME_MOCHA;
    g_theme.theme_id = tid;
    g_theme.titlebar_h = 30;
    g_theme.border_w = 1;
    g_theme.corner_radius = 6;
    g_theme.btn_size = 16;

    if (tid == THEME_MOCHA) {
        strcpy(g_theme.name, "Catppuccin Mocha");
        g_theme.bg_crust         = 0xFF11111B;
        g_theme.bg_mantle        = 0xFF181825;
        g_theme.bg_base          = 0xFF1E1E2E;
        g_theme.bg_surface0      = 0xFF313244;
        g_theme.bg_surface1      = 0xFF45475A;
        g_theme.bg_surface2      = 0xFF585B70;
        g_theme.border_subtle    = 0xFF313244;
        g_theme.border_active    = 0xFF89B4FA;
        g_theme.text_primary     = 0xFFCDD6F4;
        g_theme.text_secondary   = 0xFFBAC2DE;
        g_theme.text_muted       = 0xFF6C7086;
        g_theme.accent_primary   = 0xFF89B4FA;
        g_theme.accent_secondary = 0xFF74C7EC;
        g_theme.accent_tertiary  = 0xFFCBA6F7;
        g_theme.accent_cyan      = 0xFF89DCEB;
        g_theme.accent_teal      = 0xFF94E2D5;
        g_theme.status_success   = 0xFFA6E3A1;
        g_theme.status_warning   = 0xFFF9E2AF;
        g_theme.status_peach     = 0xFFFAB387;
        g_theme.status_danger    = 0xFFF38BA8;
        g_theme.glass_tint       = 0xC8181825;
        g_theme.shadow_color     = 0x4011111B;
    } else if (tid == THEME_LATTE) {
        strcpy(g_theme.name, "Catppuccin Latte");
        g_theme.bg_crust         = 0xFFDCE0E8;
        g_theme.bg_mantle        = 0xFFE6E9EF;
        g_theme.bg_base          = 0xFFEFF1F5;
        g_theme.bg_surface0      = 0xFFCCD0DA;
        g_theme.bg_surface1      = 0xFFBCC0CC;
        g_theme.bg_surface2      = 0xFFACB0BE;
        g_theme.border_subtle    = 0xFFBCC0CC;
        g_theme.border_active    = 0xFF1E66F5;
        g_theme.text_primary     = 0xFF4C4F69;
        g_theme.text_secondary   = 0xFF5C5F77;
        g_theme.text_muted       = 0xFF8C8FA1;
        g_theme.accent_primary   = 0xFF1E66F5;
        g_theme.accent_secondary = 0xFF209FB5;
        g_theme.accent_tertiary  = 0xFF8839EF;
        g_theme.accent_cyan      = 0xFF04A5E5;
        g_theme.accent_teal      = 0xFF179299;
        g_theme.status_success   = 0xFF40A02B;
        g_theme.status_warning   = 0xFFDF8E1D;
        g_theme.status_peach     = 0xFFFE640B;
        g_theme.status_danger    = 0xFFD20F39;
        g_theme.glass_tint       = 0xC8E6E9EF;
        g_theme.shadow_color     = 0x304C4F69;
    } else if (tid == THEME_TOKYO) {
        strcpy(g_theme.name, "Tokyo Night");
        g_theme.bg_crust         = 0xFF16161E;
        g_theme.bg_mantle        = 0xFF1A1B26;
        g_theme.bg_base          = 0xFF24283B;
        g_theme.bg_surface0      = 0xFF292E42;
        g_theme.bg_surface1      = 0xFF3B4261;
        g_theme.bg_surface2      = 0xFF414868;
        g_theme.border_subtle    = 0xFF292E42;
        g_theme.border_active    = 0xFF7AA2F7;
        g_theme.text_primary     = 0xFFC0CAF5;
        g_theme.text_secondary   = 0xFFA9B1D6;
        g_theme.text_muted       = 0xFF565F89;
        g_theme.accent_primary   = 0xFF7AA2F7;
        g_theme.accent_secondary = 0xFF2AC3DE;
        g_theme.accent_tertiary  = 0xFFBB9AF7;
        g_theme.accent_cyan      = 0xFF7DCFFF;
        g_theme.accent_teal      = 0xFF73DACA;
        g_theme.status_success   = 0xFF9ECE6A;
        g_theme.status_warning   = 0xFFE0AF68;
        g_theme.status_peach     = 0xFFFF9E64;
        g_theme.status_danger    = 0xFFF7768E;
        g_theme.glass_tint       = 0xC81A1B26;
        g_theme.shadow_color     = 0x48101018;
    } else if (tid == THEME_NORD) {
        strcpy(g_theme.name, "Nord Arctic");
        g_theme.bg_crust         = 0xFF242933;
        g_theme.bg_mantle        = 0xFF2E3440;
        g_theme.bg_base          = 0xFF3B4252;
        g_theme.bg_surface0      = 0xFF434C5E;
        g_theme.bg_surface1      = 0xFF4C566A;
        g_theme.bg_surface2      = 0xFF616E88;
        g_theme.border_subtle    = 0xFF434C5E;
        g_theme.border_active    = 0xFF88C0D0;
        g_theme.text_primary     = 0xFFECEFF4;
        g_theme.text_secondary   = 0xFFE5E9F0;
        g_theme.text_muted       = 0xFFD8DEE9;
        g_theme.accent_primary   = 0xFF81A1C1;
        g_theme.accent_secondary = 0xFF88C0D0;
        g_theme.accent_tertiary  = 0xFFB48EAD;
        g_theme.accent_cyan      = 0xFF8FBCBB;
        g_theme.accent_teal      = 0xFF8FBCBB;
        g_theme.status_success   = 0xFFA3BE8C;
        g_theme.status_warning   = 0xFFEBCB8B;
        g_theme.status_peach     = 0xFFD08770;
        g_theme.status_danger    = 0xFFBF616A;
        g_theme.glass_tint       = 0xC82E3440;
        g_theme.shadow_color     = 0x401E222A;
    } else if (tid == THEME_TEMPLE) {
        strcpy(g_theme.name, "TempleOS Divine CGA");
        g_theme.bg_crust         = 0xFF000055;
        g_theme.bg_mantle        = 0xFF0000AA;
        g_theme.bg_base          = 0xFF000088;
        g_theme.bg_surface0      = 0xFF0055AA;
        g_theme.bg_surface1      = 0xFF00AAAA;
        g_theme.bg_surface2      = 0xFF55FFFF;
        g_theme.border_subtle    = 0xFF55FFFF;
        g_theme.border_active    = 0xFFFFFF55;
        g_theme.text_primary     = 0xFFFFFFFF;
        g_theme.text_secondary   = 0xFF55FFFF;
        g_theme.text_muted       = 0xFFAAAAAA;
        g_theme.accent_primary   = 0xFFFFFF55;
        g_theme.accent_secondary = 0xFF55FFFF;
        g_theme.accent_tertiary  = 0xFFFF55FF;
        g_theme.accent_cyan      = 0xFF55FFFF;
        g_theme.accent_teal      = 0xFF55FF55;
        g_theme.status_success   = 0xFF55FF55;
        g_theme.status_warning   = 0xFFFFFF55;
        g_theme.status_peach     = 0xFFFFAA00;
        g_theme.status_danger    = 0xFFFF5555;
        g_theme.glass_tint       = 0xD00000AA;
        g_theme.shadow_color     = 0x60000000;
        g_theme.corner_radius    = 0;
        g_theme.border_w         = 2;
    } else if (tid == THEME_CYBERPUNK) {
        strcpy(g_theme.name, "Cyberpunk OLED");
        g_theme.bg_crust         = 0xFF05050A;
        g_theme.bg_mantle        = 0xFF090A14;
        g_theme.bg_base          = 0xFF101224;
        g_theme.bg_surface0      = 0xFF1A1E36;
        g_theme.bg_surface1      = 0xFF282E52;
        g_theme.bg_surface2      = 0xFF384070;
        g_theme.border_subtle    = 0xFF282E52;
        g_theme.border_active    = 0xFFFF007F;
        g_theme.text_primary     = 0xFFE8F7FF;
        g_theme.text_secondary   = 0xFF00F0FF;
        g_theme.text_muted       = 0xFF6A78A0;
        g_theme.accent_primary   = 0xFFFF007F;
        g_theme.accent_secondary = 0xFF00F0FF;
        g_theme.accent_tertiary  = 0xFFBD00FF;
        g_theme.accent_cyan      = 0xFF00F0FF;
        g_theme.accent_teal      = 0xFF00FF9F;
        g_theme.status_success   = 0xFF00FF9F;
        g_theme.status_warning   = 0xFFFCEE09;
        g_theme.status_peach     = 0xFFFF6600;
        g_theme.status_danger    = 0xFFFF0055;
        g_theme.glass_tint       = 0xC8090A14;
        g_theme.shadow_color     = 0x60000000;
    }
}

I64 ThemeSetByName(U8 *tname) {
    if (!tname || !*tname) return g_theme.theme_id;
    while (*tname == ' ') tname++;
    if (strncmp(tname, "mocha", 5) == 0 || strcmp(tname, "0") == 0) {
        ThemeApply(THEME_MOCHA);
    } else if (strncmp(tname, "latte", 5) == 0 || strcmp(tname, "1") == 0 || strncmp(tname, "light", 5) == 0) {
        ThemeApply(THEME_LATTE);
    } else if (strncmp(tname, "tokyo", 5) == 0 || strcmp(tname, "2") == 0) {
        ThemeApply(THEME_TOKYO);
    } else if (strncmp(tname, "nord", 4) == 0 || strcmp(tname, "3") == 0) {
        ThemeApply(THEME_NORD);
    } else if (strncmp(tname, "temple", 6) == 0 || strcmp(tname, "4") == 0 || strncmp(tname, "cga", 3) == 0) {
        ThemeApply(THEME_TEMPLE);
    } else if (strncmp(tname, "cyber", 5) == 0 || strcmp(tname, "5") == 0 || strncmp(tname, "oled", 4) == 0) {
        ThemeApply(THEME_CYBERPUNK);
    } else {
        // Cycle to next theme
        ThemeApply((g_theme.theme_id + 1) % THEME_COUNT);
    }
    return g_theme.theme_id;
}
