#pragma once
#include <algorithm>
#include <cmath>

// Phase 4 Part 4.1: per-instance passive-tree view state (zoom + pan +
// viewport size), split out of the shared TreeViewController so several
// TreeScene instances can show the same build's tree at different zoom/pan —
// exactly as legacy creates one PassiveTreeView per embed (TreeTab.viewer,
// ItemsTab.socketViewer, CalcBreakdownControl.nodeViewer, the timeless-jewel
// socketViewer) over a single shared spec.
//
// Header-only and free of Qt Quick so the shared headless selftest suite can
// exercise it in the Core-only pob-selftest binary.
//
// Screen mapping (identical to legacy PassiveTreeView:Draw):
//     scale  = min(vpW, vpH) / treeSize * zoom
//     screen = vp/2 + zoomOffset + scale * treeCoord
class TreeViewport {
public:
    static constexpr double kMinLevel = 0.0;
    static constexpr double kMaxLevel = 12.0;
    // Default view opens zoomed in near the tree centre (class start), matching
    // legacy PoB, rather than fit-whole-tree. zoom = 1.2^level, so 8 ≈ 4.3x.
    static constexpr double kDefaultLevel = 8.0;

    // --- inputs -----------------------------------------------------------
    // Returns true if the pan offset had to be re-clamped.
    bool setViewport(double w, double h) {
        m_vpW = w;
        m_vpH = h;
        return clampPan();
    }
    // Tree geometry from the controller: bounds.size and the per-axis max
    // absolute extent of any node (for the pan clamp).
    bool setTreeExtent(double size, double extentX, double extentY) {
        m_size = size;
        m_extentX = extentX;
        m_extentY = extentY;
        return clampPan();
    }

    // --- state ------------------------------------------------------------
    double zoomLevel() const { return m_level; }
    // A focused (embed) view may carry a raw zoom factor that is not a power
    // of 1.2 — legacy embeds assign `viewer.zoom` directly (17 for the jewel
    // socket viewer, 5 for the Calcs breakdown node view).
    double zoom() const { return m_rawZoom > 0.0 ? m_rawZoom : std::pow(1.2, m_level); }
    double zoomX() const { return m_zoomX; }
    double zoomY() const { return m_zoomY; }
    double viewportWidth() const { return m_vpW; }
    double viewportHeight() const { return m_vpH; }
    bool valid() const { return m_size > 0.0 && m_vpW > 0.0 && m_vpH > 0.0; }

    double baseScale() const {
        return valid() ? std::min(m_vpW, m_vpH) / m_size : 0.0;
    }
    double scale() const { return baseScale() * zoom(); }

    // --- coordinate conversion -------------------------------------------
    void treeToScreen(double tx, double ty, double& sx, double& sy) const {
        const double s = scale();
        sx = tx * s + m_zoomX + m_vpW / 2.0;
        sy = ty * s + m_zoomY + m_vpH / 2.0;
    }
    bool screenToTree(double sx, double sy, double& tx, double& ty) const {
        const double s = scale();
        if (!(s > 0.0))
            return false;
        tx = (sx - m_zoomX - m_vpW / 2.0) / s;
        ty = (sy - m_zoomY - m_vpH / 2.0) / s;
        return true;
    }

    // --- interactive mutations (clamped) ---------------------------------
    // Returns true if anything changed.
    bool setZoomLevel(double level) {
        level = std::min(std::max(level, kMinLevel), kMaxLevel);
        const bool changed = level != m_level || m_rawZoom > 0.0;
        m_level = level;
        m_rawZoom = 0.0;
        clampPan();
        return changed;
    }
    bool setZoomX(double v) { return setPan(v, m_zoomY); }
    bool setZoomY(double v) { return setPan(m_zoomX, v); }
    bool panBy(double dx, double dy) { return setPan(m_zoomX + dx, m_zoomY + dy); }

    // Legacy PassiveTreeView:Zoom — step the level and keep the tree point under
    // the cursor (viewport-local pixels) fixed on screen.
    bool zoomAt(double delta, double cursorX, double cursorY) {
        const double oldZoom = zoom();
        const double oldX = m_zoomX, oldY = m_zoomY, oldLevel = m_level;
        m_level = std::min(std::max(m_level + delta, kMinLevel), kMaxLevel);
        m_rawZoom = 0.0;
        const double factor = zoom() / oldZoom;
        const double relX = cursorX - m_vpW / 2.0;
        const double relY = cursorY - m_vpH / 2.0;
        m_zoomX = relX + (m_zoomX - relX) * factor;
        m_zoomY = relY + (m_zoomY - relY) * factor;
        clampPan();
        return m_level != oldLevel || m_zoomX != oldX || m_zoomY != oldY;
    }

    void reset() {
        m_level = kDefaultLevel;
        m_rawZoom = 0.0;
        m_zoomX = 0.0;
        m_zoomY = 0.0;
    }

    // Centre a tree point, at a raw zoom factor (legacy embed semantics:
    // `viewer.zoom = z; viewer.zoomX = -node.x * scale`). zoomFactor <= 0 keeps
    // the current zoom. NOT pan-clamped: the interactive clamp keeps the rim
    // node at the viewport EDGE, so it would refuse to centre an outer node —
    // legacy's own clamp (±vp*zoom*2/3) never binds for an in-tree point.
    void focus(double tx, double ty, double zoomFactor) {
        if (zoomFactor > 0.0)
            m_rawZoom = zoomFactor;
        const double s = scale();
        m_zoomX = -tx * s;
        m_zoomY = -ty * s;
    }

private:
    bool setPan(double x, double y) {
        const double oldX = m_zoomX, oldY = m_zoomY;
        m_zoomX = x;
        m_zoomY = y;
        clampPan();
        return m_zoomX != oldX || m_zoomY != oldY;
    }

    // Clamp the pan so the tree can't be dragged into empty canvas past its
    // border, while never cropping the outermost nodes. (Legacy's literal
    // `viewport * zoom * 2/3` formula is calibrated to its own tree->screen
    // scale and does NOT transfer, so the bound is derived from geometry.)
    // Allowing |zoomOffset| up to `extent*scale - vp/2` lets the farthest node
    // travel exactly to the viewport edge; the margin (a node's on-screen
    // half-extent, ~85 sheet-units * 2.66 / 2) keeps it fully inside rather than
    // half-clipped. When the whole tree fits, the bound is 0 -> locked.
    bool clampPan() {
        // A raw-zoom focus is an embed's fixed framing; see focus().
        if (!valid() || m_rawZoom > 0.0)
            return false;
        const double s = scale();
        const double nodeMargin = 85.0 * s * 2.66 / 2.0;
        const double maxX = std::max(0.0, m_extentX * s - m_vpW / 2.0 + nodeMargin);
        const double maxY = std::max(0.0, m_extentY * s - m_vpH / 2.0 + nodeMargin);
        const double cx = std::min(std::max(m_zoomX, -maxX), maxX);
        const double cy = std::min(std::max(m_zoomY, -maxY), maxY);
        if (cx == m_zoomX && cy == m_zoomY)
            return false;
        m_zoomX = cx;
        m_zoomY = cy;
        return true;
    }

    double m_level = kDefaultLevel;
    double m_rawZoom = 0.0; // > 0 only while a focus() raw zoom is in effect
    double m_zoomX = 0.0;
    double m_zoomY = 0.0;
    double m_vpW = 0.0;
    double m_vpH = 0.0;
    double m_size = 0.0;
    double m_extentX = 0.0;
    double m_extentY = 0.0;
};
