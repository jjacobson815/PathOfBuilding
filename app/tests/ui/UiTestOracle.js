var RESOLUTIONS = [
    { name: "960x640",   w: 960,  h: 640 },
    { name: "1100x720",  w: 1100, h: 720 },
    { name: "1600x900",  w: 1600, h: 900 }
];

function step(tc, label) {
    var delay = (typeof uiTest !== "undefined" && uiTest && uiTest.stepDelayMs)
        ? uiTest.stepDelayMs() : 0;
    if (delay > 0) {
        console.log("[ui-step] " + (label || ""));
        tc.wait(delay);
    }
}

function assertZeroWarnings(tc, uiTest, label) {
    var warns = uiTest.warnings();
    if (warns.length > 0) {
        tc.fail((label || "ZeroWarnings") + " emitted " + warns.length + " QML warning(s):\n  " + warns.join("\n  "));
    }
}

function findRequired(tc, uiTest, root, objectName) {
    var obj = uiTest.findObject(root, objectName);
    tc.verify(obj !== null && obj !== undefined, "Missing expected objectName: " + objectName);
    return obj;
}

function assertMultiResLayout(tc, hostContainer, targetObj, uiTest, label, restoreW, restoreH, options) {
    var origW = restoreW !== undefined ? restoreW : hostContainer.width;
    var origH = restoreH !== undefined ? restoreH : hostContainer.height;
    for (var i = 0; i < RESOLUTIONS.length; i++) {
        var r = RESOLUTIONS[i];
        hostContainer.width = r.w;
        hostContainer.height = r.h;
        tc.wait(25);
        var res = uiTest.checkLayoutOracle(targetObj || hostContainer, r.w, r.h, options || ({}));
        if (!res.ok) {
            var issues = res.issues || [];
            var artifact = "";
            if (uiTest.captureAnnotatedFailure) {
                artifact = uiTest.captureAnnotatedFailure(hostContainer, res.violations || issues, "");
            }
            tc.fail((label || "LayoutOracle") + " failed at " + r.name
                    + (artifact ? (" [artifact: " + artifact + "]") : "")
                    + ":\n  " + issues.join("\n  "));
        }
    }
    hostContainer.width = origW;
    hostContainer.height = origH;
    tc.wait(15);
}
