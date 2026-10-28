pragma ComponentBehavior: Bound

import QtQuick

// a layer effect correcting colors for color blindness like KWin's effect does on the desktop, see colorcorrection.frag
ShaderEffect {
    // 1 protanopia, 2 deuteranopia, 3 tritanopia, 4 monochrome
    property int mode: 1
    property real intensity: 1

    fragmentShader: "colorcorrection.frag.qsb"
}
