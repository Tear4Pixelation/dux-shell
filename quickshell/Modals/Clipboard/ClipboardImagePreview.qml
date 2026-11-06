pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

// Side preview for image entries: an xdg_popup outside the clipboard surface,
// beside it, with the card's top edge level with the previewed entry's top.
PopupWindow {
    id: root

    // Item whose left/right edges the preview sits beside (the clipboard content).
    required property Item anchorItem
    // Top of the previewed entry, in anchorItem coordinates.
    property real entryTop: 0
    property var entry: null
    property bool shown: false

    property string cachedImageData: ""
    property string cachedMimeType: ""
    property var requestedEntryId: null

    readonly property string sourceUrl: ClipboardService.imageDataUrl(cachedImageData, cachedMimeType || (entry?.mimeType ?? ""))
    readonly property real sideGap: Theme.spacingM
    readonly property real shadowPadding: Theme.elevationRenderPadding(Theme.elevationLevel2, Theme.elevationLightDirection, Theme.spacingXS, Theme.spacingS, Theme.spacingL)
    readonly property real maxCardWidth: ClipboardConstants.previewMaxWidth
    readonly property real maxCardHeight: ClipboardConstants.previewMaxHeight
    readonly property real minCardSize: ClipboardConstants.previewMinSize

    // Keep the last fitted size while the next image loads so the card does not jump.
    property real cardWidth: minCardSize
    property real cardHeight: minCardSize

    function fitCardToImage() {
        const naturalWidth = previewImage.implicitWidth;
        const naturalHeight = previewImage.implicitHeight;
        if (naturalWidth <= 0 || naturalHeight <= 0)
            return;
        const scale = Math.min(maxCardWidth / naturalWidth, maxCardHeight / naturalHeight, 1);
        cardWidth = Math.max(minCardSize, Math.round(naturalWidth * scale));
        cardHeight = Math.max(minCardSize, Math.round(naturalHeight * scale));
    }

    function loadEntry() {
        if (!ClipboardService.canPreviewEntry(entry)) {
            requestedEntryId = null;
            cachedImageData = "";
            cachedMimeType = "";
            return;
        }
        if (entry.id === requestedEntryId)
            return;

        cachedImageData = "";
        cachedMimeType = "";
        const entryId = entry.id;
        requestedEntryId = entryId;
        DMSService.sendRequest("clipboard.getEntry", {
            "id": entryId
        }, function (response) {
            if (root.requestedEntryId !== entryId)
                return;
            if (response.error) {
                root.requestedEntryId = null;
                return;
            }
            if (!response.result) {
                root.requestedEntryId = null;
                ClipboardService.refresh();
                return;
            }
            const mimeType = (response.result.mimeType ?? root.entry?.mimeType ?? "").toString();
            const data = (response.result.data ?? "").toString();
            if (!ClipboardService.imageDataUrl(data, mimeType)) {
                root.requestedEntryId = null;
                return;
            }
            root.cachedMimeType = mimeType;
            root.cachedImageData = data;
        });
    }

    onEntryChanged: loadEntry()
    // Item-anchored popups do not follow rect changes on their own; reposition once the
    // anchor.rect bindings have taken the new value.
    onEntryTopChanged: {
        if (visible)
            Qt.callLater(() => root.anchor.updateAnchor());
    }
    Component.onCompleted: loadEntry()

    visible: shown && !!entry
    color: "transparent"
    mask: Region {}
    implicitWidth: cardWidth + shadowPadding * 2
    implicitHeight: cardHeight + shadowPadding * 2

    // The anchor rect spans the content plus the gap on both sides, so the popup sits
    // just outside the leading edge and flips to the trailing edge when there is no room.
    anchor.item: anchorItem
    anchor.rect.x: -sideGap + shadowPadding
    anchor.rect.y: entryTop - shadowPadding
    anchor.rect.width: Math.max(1, (anchorItem?.width ?? 0) + (sideGap - shadowPadding) * 2)
    anchor.rect.height: 1
    anchor.edges: I18n.isRtl ? (Edges.Top | Edges.Right) : (Edges.Top | Edges.Left)
    anchor.gravity: I18n.isRtl ? (Edges.Bottom | Edges.Right) : (Edges.Bottom | Edges.Left)
    anchor.adjustment: PopupAdjustment.FlipX | PopupAdjustment.SlideY

    WindowBlur {
        targetWindow: root
        surfaceColor: card.color
        blurX: card.x
        blurY: card.y
        blurWidth: root.visible ? card.width : 0
        blurHeight: root.visible ? card.height : 0
        blurRadius: card.radius
    }

    Rectangle {
        id: card

        x: root.shadowPadding
        y: root.shadowPadding
        width: root.cardWidth
        height: root.cardHeight
        radius: Theme.windowRadius
        color: Theme.readableSurface
        border.color: BlurService.borderColor
        border.width: BlurService.borderWidth

        ElevationShadow {
            anchors.fill: parent
            z: -1
            level: Theme.elevationLevel2
            targetRadius: parent.radius
            targetColor: "transparent"
            shadowEnabled: Theme.elevationEnabled
        }

        ClippingRectangle {
            anchors.fill: parent
            anchors.margins: card.border.width
            radius: Math.max(0, card.radius - card.border.width)
            color: "transparent"

            Image {
                id: previewImage

                anchors.fill: parent
                source: root.sourceUrl
                asynchronous: true
                cache: false
                smooth: true
                mipmap: true
                fillMode: Image.PreserveAspectFit
                // Decode at up to 2x the card size so HiDPI outputs stay sharp.
                sourceSize.width: root.maxCardWidth * 2
                sourceSize.height: root.maxCardHeight * 2
                visible: status === Image.Ready && source != ""
                onStatusChanged: {
                    if (status === Image.Ready)
                        root.fitCardToImage();
                }
            }
        }

        DIcon {
            anchors.centerIn: parent
            name: "image"
            size: Theme.iconSizeLarge
            color: Theme.primary
            visible: !previewImage.visible
        }
    }
}
