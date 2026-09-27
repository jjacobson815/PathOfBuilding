#include "TintedTextureMaterial.h"
#include <cstring>

const QSGGeometry::AttributeSet& tintedTextureAttributes() {
    static const QSGGeometry::Attribute attrs[] = {
        QSGGeometry::Attribute::createWithAttributeType(0, 2, QSGGeometry::FloatType, QSGGeometry::PositionAttribute),
        QSGGeometry::Attribute::createWithAttributeType(1, 2, QSGGeometry::FloatType, QSGGeometry::TexCoordAttribute),
        QSGGeometry::Attribute::createWithAttributeType(2, 4, QSGGeometry::UnsignedByteType, QSGGeometry::ColorAttribute),
    };
    static const QSGGeometry::AttributeSet set = { 3, int(sizeof(TintedVertex)), attrs };
    return set;
}

namespace {
class TintedTextureShader : public QSGMaterialShader {
public:
    TintedTextureShader() {
        setShaderFileName(VertexStage, QStringLiteral(":/shaders/tintedtexture.vert.qsb"));
        setShaderFileName(FragmentStage, QStringLiteral(":/shaders/tintedtexture.frag.qsb"));
    }
    bool updateUniformData(RenderState& state, QSGMaterial*, QSGMaterial*) override {
        QByteArray* buf = state.uniformData();
        bool changed = false;
        if (state.isMatrixDirty()) {
            const QMatrix4x4 m = state.combinedMatrix();
            std::memcpy(buf->data(), m.constData(), 64);
            changed = true;
        }
        if (state.isOpacityDirty()) {
            const float opacity = state.opacity();
            std::memcpy(buf->data() + 64, &opacity, 4);
            changed = true;
        }
        return changed;
    }
    void updateSampledImage(RenderState& state, int binding, QSGTexture** texture,
                            QSGMaterial* newMaterial, QSGMaterial*) override {
        if (binding != 1)
            return;
        auto* mat = static_cast<TintedTextureMaterial*>(newMaterial);
        QSGTexture* t = mat->texture();
        if (t)
            t->commitTextureOperations(state.rhi(), state.resourceUpdateBatch());
        *texture = t;
    }
};
}

TintedTextureMaterial::TintedTextureMaterial() {
    setFlag(Blending, true);
}

QSGMaterialType* TintedTextureMaterial::type() const {
    static QSGMaterialType t;
    return &t;
}

QSGMaterialShader* TintedTextureMaterial::createShader(QSGRendererInterface::RenderMode) const {
    return new TintedTextureShader;
}

int TintedTextureMaterial::compare(const QSGMaterial* other) const {
    const auto* o = static_cast<const TintedTextureMaterial*>(other);
    const qint64 a = m_texture ? m_texture->comparisonKey() : 0;
    const qint64 b = o->m_texture ? o->m_texture->comparisonKey() : 0;
    return a == b ? 0 : (a < b ? -1 : 1);
}
