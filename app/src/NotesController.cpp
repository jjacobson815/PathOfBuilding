#include "NotesController.h"
#include "LuaEngine.h"

#include <QDebug>

NotesController::NotesController(QObject* parent) : QObject(parent) {}

void NotesController::setNotes(const QString& text) {
    if (m_notes == text)
        return;
    m_notes = text;
    emit notesChanged();
    if (m_engine)
        m_engine->setNotes(text);
}

void NotesController::refresh(LuaEngine* engine) {
    if (!engine)
        return;
    m_engine = engine;
    QString cur = engine->getNotes();
    if (m_loaded && cur == m_notes)
        return;
    m_notes = cur;
    m_loaded = true;
    emit notesChanged();
}
