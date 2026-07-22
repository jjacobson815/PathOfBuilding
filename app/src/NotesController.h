#pragma once
#include <QObject>
#include <QString>

class LuaEngine;

// Phase 5e: NotesTab (NOTES view) controller. Mirrors the NotesTab edit buffer
// (self.controls.edit.buf) onto a QML-bindable `notes` QString. refresh() pulls
// the current notes text from the engine via LuaEngine::getNotes() (which calls
// the pob_getNotes Lua global); setNotes() writes back via LuaEngine::setNotes()
// (pob_setNotes). Linked ONLY into pob-qt (never pob-selftest) like the other
// view models.
class NotesController : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString notes READ notes WRITE setNotes NOTIFY notesChanged)

public:
    explicit NotesController(QObject* parent = nullptr);

    QString notes() const { return m_notes; }
    // QML write entry point: update the local mirror and push to the engine.
    Q_INVOKABLE void setNotes(const QString& text);

    // Pull the current notes text from the engine (throttled by a content
    // signature so the per-frame call from the frame loop is cheap). Also
    // caches the engine pointer so setNotes() can reach it.
    void refresh(LuaEngine* engine);

signals:
    void notesChanged();

private:
    QString m_notes;
    LuaEngine* m_engine = nullptr;
    bool m_loaded = false;
};
