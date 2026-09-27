#pragma once
#include <QSGMaterial>
#include <QSGMaterialShader>
#include <QSGGeometry>
#include <QSGTexture>

// Phase 4 Part 4.3: textured quads multiplied by a per-vertex colour — the
// scene-graph equivalent of legacy's SetDrawColor before DrawImage/
// DrawImageQuad. QSGTextureMaterial cannot tint, and the tree needs tinting
// for the heat map, compare overlay, red dependents and jewel-radius colours.
//
// The shaders are pre-baked .qsb files (app/shaders/, qrc prefix /shaders),
// so building needs no Qt Shader Tools.

struct TintedVertex {
    float x, y;
    float u, v;
    unsigned char r, g, b, a;
    void set(float px, float py, float tu, float tv, quint32 rgba) {
        x = px; y = py; u = tu; v = tv;
        r = (rgba >> 24) & 0xff; g = (rgba >> 16) & 0xff; b = (rgba >> 8) & 0xff; a = rgba & 0xff;
    }
};

const QSGGeometry::AttributeSet& tintedTextureAttributes();

class TintedTextureMaterial : public QSGMaterial {
public:
    TintedTextureMaterial();
    QSGMaterialType* type() const override;
    QSGMaterialShader* createShader(QSGRendererInterface::RenderMode) const override;
    int compare(const QSGMaterial* other) const override;

    void setTexture(QSGTexture* t) { m_texture = t; }
    QSGTexture* texture() const { return m_texture; }

private:
    QSGTexture* m_texture = nullptr;
};
