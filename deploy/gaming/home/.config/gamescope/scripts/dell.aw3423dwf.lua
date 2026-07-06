-- Alienware AW3423DWF (DEL, product 41489 / 0xA211) — DP-2, gaming desktop
--
-- Why this file exists:
--   gamescope only knows per-display refresh switching for panels with a
--   "known display" profile (Deck, Ally, Legion Go...). Unknown displays fall
--   back to CVT mode generation, which produces timings this panel cannot
--   lock (it needs its EDID's tight reduced blanking). Result: black screen
--   on any refresh change, and no per-game refresh dropdown in Steam.
--
-- Two timing bands, both taken verbatim from the panel's EDID
-- (edid-decode 2026-07-04):
--   Low  (<=100 Hz): DTD4  3440x1440  99.982 Hz, 538.370 MHz (no DSC)
--                    Hfront 14, Hsync 32, Hback  80 -> htotal 3566
--                    Vfront  3, Vsync 10, Vback  57 -> vtotal 1510
--   High (>100 Hz):  DTD   3440x1440 164.900 Hz, 1019.280 MHz (needs DSC)
--                    Hfront 48, Hsync 32, Hback  80 -> htotal 3600
--                    Vfront  3, Vsync 10, Vback 264 -> vtotal 1717
-- Intermediate rates stretch the vertical front porch at fixed pixel clock
-- (the same VRR-style trick Valve uses for the Deck panels; panel range is
-- 48-165 Hz, line rate stays within the panel's declared limits).
--
-- History:
--   2026-07-03: rates were capped at 100 Hz on the theory that the DSC
--   mode's atomic commit is EINVAL-rejected on linux-cachyos (worked on
--   Valve's 6.16-valve neptune kernel).
--   2026-07-04: two findings invalidated that test matrix:
--     (1) vtotal used floor(), so the "100 Hz" entry computed vfp=2 (<3),
--         hit the safety fallback, and silently returned base_mode — the
--         native 164.9 Hz DSC mode. Real 100 Hz was never tested.
--         Fixed: round-to-nearest (lands exactly on both EDID DTDs) and
--         vfp clamped to the DTD-legal minimum of 3 instead of bailing.
--     (2) All crash tests ran with the aux ViewSonic (HDMI-A-1) attached;
--         kernel logged infoframe EINVAL on that connector. It is now
--         disabled pre-switch (deckshift v0.1.11 pattern).
--   Full 48-165 range restored for a clean retest.

local aw3423dwf_refresh_rates = { 48, 50, 55, 60, 65, 72, 80, 90, 100, 120, 144, 165 }

gamescope.config.known_displays.aw3423dwf = {
    pretty_name = "Alienware AW3423DWF (DP)",
    dynamic_refresh_rates = aw3423dwf_refresh_rates,
    dynamic_modegen = function(base_mode, refresh)
        debug("Generating mode "..refresh.."Hz for AW3423DWF")
        local mode = base_mode
        gamescope.modegen.set_resolution(mode, 3440, 1440)

        local vsync, vback
        if refresh > 100 then
            -- DSC band: EDID 164.9 Hz DTD timings
            mode.clock = 1019280 -- kHz
            gamescope.modegen.set_h_timings(mode, 48, 32, 80)
            vsync, vback = 10, 264
        else
            -- non-DSC band: EDID DTD4 timings
            mode.clock = 538370 -- kHz
            gamescope.modegen.set_h_timings(mode, 14, 32, 80)
            vsync, vback = 10, 57
        end

        -- Round to nearest so the anchor rates reproduce their EDID DTDs
        -- exactly (100 -> vtotal 1510, 165 -> vtotal 1717 via vfp clamp).
        local vtotal = math.floor((mode.clock * 1000) / (mode.htotal * refresh) + 0.5)
        local vfp = vtotal - 1440 - vsync - vback
        if vfp < 3 then
            -- Clamp into DTD-legal territory (sub-Hz below the requested
            -- rate) instead of silently falling back to base_mode, which
            -- masked the real mode being driven (2026-07-04 finding).
            vfp = 3
        end
        gamescope.modegen.set_v_timings(mode, vfp, vsync, vback)

        mode.vrefresh = gamescope.modegen.calc_vrefresh(mode)
        return mode
    end,
    matches = function(display)
        if display.vendor == "DEL" and display.product == 41489 then
            debug("[aw3423dwf] Matched DEL product 41489 (0xA211)")
            return 5000
        end
        return -1
    end
}
debug("Registered Alienware AW3423DWF as a known display")
