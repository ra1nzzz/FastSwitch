// InputLeap listens at the HID event tap. Run from the AX-authorized Hammerspoon session.
ObjC.import('CoreGraphics')

function run(args) {
    const keyCodes = { j: 38, m: 46 }
    const keyCode = keyCodes[args[0]]
    if (keyCode === undefined) throw Error('Expected j or m')

    const modifiers = [59, 58, 55] // Left Control, Option, Command
    const flags = [1 << 18, 1 << 19, 1 << 20]
    let mask = 0

    function post(key, down) {
        const event = $.CGEventCreateKeyboardEvent(null, key, down)
        $.CGEventSetFlags(event, mask)
        $.CGEventPost(0, event)
        delay(0.015)
    }

    modifiers.forEach((key, i) => {
        mask |= flags[i]
        post(key, true)
    })
    post(keyCode, true)
    post(keyCode, false)
    for (let i = modifiers.length - 1; i >= 0; i--) {
        mask &= ~flags[i]
        post(modifiers[i], false)
    }
}
