pragma ComponentBehavior: Bound

import QtQuick

// a layer effect rounding the corners of its item, cheaper than OpacityMask, which renders a mask texture too
ShaderEffect {
    property real radius: 0
    readonly property size itemSize: Qt.size(width, height)

    fragmentShader: "roundedcorners.frag.qsb"
}
