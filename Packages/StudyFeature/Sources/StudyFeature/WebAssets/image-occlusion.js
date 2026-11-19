// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
// Adapted from ts/routes/image-occlusion/review.ts in Hayaki's pinned Anki.

(() => {
    "use strict";

    const maskColor = "#ffeba2";
    const selectors = ["cloze", "cloze-inactive", "cloze-highlight"];
    const sessions = new WeakMap();
    const numeric = (value, fallback = 0) => Number.isFinite(Number(value)) ? Number(value) : fallback;

    class Shape {
        constructor(data = {}) {
            Object.assign(this, data);
            this.left = numeric(data.left);
            this.top = numeric(data.top);
            this.angle = numeric(data.angle);
            this.fill = data.fill ?? maskColor;
        }

        toAbsolute(size) {
            return new this.constructor({
                ...this,
                left: this.left * size.width,
                top: this.top * size.height,
            });
        }
    }

    class Rectangle extends Shape {
        toAbsolute(size) {
            const shape = super.toAbsolute(size);
            shape.width *= size.width;
            shape.height *= size.height;
            return shape;
        }
    }

    class Ellipse extends Shape {
        toAbsolute(size) {
            const shape = super.toAbsolute(size);
            shape.rx *= size.width;
            shape.ry *= size.height;
            return shape;
        }
    }

    class Polygon extends Shape {
        toAbsolute(size) {
            const shape = super.toAbsolute(size);
            shape.points = this.points.map(({ x, y }) => ({ x: x * size.width, y: y * size.height }));
            return shape;
        }
    }

    class Text extends Shape {
        constructor(data) {
            super(data);
            this.fill = data.fill ?? "#000";
        }

        toAbsolute(size) {
            const shape = super.toAbsolute(size);
            shape.fontSize = this.fontSize ? this.fontSize * size.height : 40;
            return shape;
        }
    }

    function shapeFromElement(element) {
        const data = element.dataset;
        const common = {
            left: numeric(data.left), top: numeric(data.top), angle: numeric(data.angle) * 360 / 10000,
            fill: data.fill, occludeInactive: data.occludeinactive === "1",
            ordinal: parseInt(data.ordinal, 10),
        };
        switch (data.shape) {
        case "rect":
            return new Rectangle({ ...common, width: numeric(data.width), height: numeric(data.height) });
        case "ellipse":
            return new Ellipse({ ...common, rx: numeric(data.rx), ry: numeric(data.ry) });
        case "polygon": {
            const points = (data.points ?? "").trim().split(/\s+/).map(pair => pair.split(",").map(Number))
                .filter(([x, y]) => Number.isFinite(x) && Number.isFinite(y)).map(([x, y]) => ({ x, y }));
            return points.length > 2 ? new Polygon({ ...common, points }) : null;
        }
        case "text":
            return new Text({
                ...common, text: data.text ?? "", fontSize: numeric(data.fontSize),
                scaleX: numeric(data.scale, 1), scaleY: numeric(data.scale, 1),
            });
        default:
            return null;
        }
    }

    function drawShape({ context, size, shape, fill, stroke, strokeWidth }) {
        const ctx = context;
        shape = shape.toAbsolute(size);
        const { left, top } = shape;
        ctx.save();
        ctx.translate(left, top);
        ctx.rotate(shape.angle * Math.PI / 180);
        ctx.fillStyle = fill;
        ctx.strokeStyle = stroke;
        ctx.lineWidth = strokeWidth || 1;
        if (shape instanceof Rectangle) {
            ctx.fillRect(0, 0, shape.width, shape.height);
            if (strokeWidth) ctx.strokeRect(0, 0, shape.width, shape.height);
        } else if (shape instanceof Ellipse && shape.rx > 0 && shape.ry > 0) {
            ctx.beginPath();
            ctx.ellipse(shape.rx, shape.ry, shape.rx, shape.ry, 0, 0, Math.PI * 2);
            ctx.fill();
            if (strokeWidth) ctx.stroke();
        } else if (shape instanceof Polygon && shape.points.length) {
            const minX = Math.min(...shape.points.map(point => point.x));
            const minY = Math.min(...shape.points.map(point => point.y));
            const [first, ...rest] = shape.points;
            ctx.beginPath();
            ctx.moveTo(first.x - minX, first.y - minY);
            for (const point of rest) ctx.lineTo(point.x - minX, point.y - minY);
            ctx.closePath();
            ctx.fill();
            if (strokeWidth) ctx.stroke();
        } else if (shape instanceof Text) {
            ctx.font = `${shape.fontSize}px Arial`;
            ctx.textBaseline = "top";
            ctx.scale(shape.scaleX, shape.scaleY);
            const lines = shape.text.split("\n");
            const metrics = ctx.measureText("M");
            const lineHeight = 1.5 * (metrics.actualBoundingBoxAscent + metrics.actualBoundingBoxDescent);
            ctx.fillStyle = "#fff";
            ctx.fillRect(0, 0, Math.max(...lines.map(line => ctx.measureText(line).width)) + 5,
                lines.length * lineHeight + 5);
            ctx.fillStyle = shape.fill;
            lines.forEach((line, index) => ctx.fillText(line, 0, index * lineHeight));
        }
        ctx.restore();
    }

    function shapeColors(canvas) {
        const style = getComputedStyle(canvas);
        const variable = (name, fallback) => style.getPropertyValue(name).trim() || fallback;
        const border = (name, fallback) => {
            const value = variable(name, `1px ${fallback}`);
            const [, width, color] = value.match(/^(\S+)\s+(.+)$/) ?? [];
            return { width: Number.isNaN(parseFloat(width)) ? 1 : parseFloat(width), color: color || fallback };
        };
        return {
            activeShapeColor: variable("--active-shape-color", "#ff8e8e"),
            inActiveShapeColor: variable("--inactive-shape-color", maskColor),
            highlightShapeColor: variable("--highlight-shape-color", "#ff8e8e00"),
            activeBorder: border("--active-shape-border", "#212121"),
            inActiveBorder: border("--inactive-shape-border", "#212121"),
            highlightShapeBorder: border("--highlight-shape-border", "#ff8e8e"),
        };
    }

    function setup(options = {}) {
        const canvas = document.getElementById("image-occlusion-canvas");
        const container = document.getElementById("image-occlusion-container");
        const img = container?.querySelector("img");
        if (!canvas || !img || sessions.has(canvas)) return;
        const button = document.getElementById("toggle");
        let hidden = false;

        function draw() {
            if (!canvas.isConnected || !img.naturalWidth || !img.naturalHeight) return;
            const ratio = img.naturalWidth / img.naturalHeight;
            const style = getComputedStyle(container);
            const maxHeight = parseFloat(style.maxHeight) || img.naturalHeight;
            const maxWidth = parseFloat(style.maxWidth) || Infinity;
            const width = Math.min(container.parentElement.clientWidth, maxWidth, maxHeight * ratio);
            container.style.width = `${width}px`;
            container.style.aspectRatio = String(ratio);
            // Safari limits total canvas area to 16 megapixels.
            const pixels = Math.min(devicePixelRatio, 4096 * Math.sqrt(ratio) / width);
            canvas.width = Math.max(1, Math.floor(width * pixels));
            canvas.height = Math.max(1, Math.floor(width * pixels / ratio));
            const context = canvas.getContext("2d");
            if (!context) return;
            const [activeShapes, inactiveShapes, highlightShapes] = selectors.map(name =>
                Array.from(document.querySelectorAll(`#qa .${name}[data-shape]`), shapeFromElement)
                    .filter(shape => shape && (!hidden || shape instanceof Text)));
            const before = { activeShapes, inactiveShapes, highlightShapes, properties: shapeColors(canvas) };
            const after = options.onWillDrawShapes?.(before, context) ?? before;
            const properties = after.properties;
            function drawLayer(shapes, fill, border) {
                for (const shape of shapes) {
                    drawShape({ context, size: canvas, shape, fill: fill(shape), stroke: border.color, strokeWidth: border.width });
                }
            }
            drawLayer(after.activeShapes, () => properties.activeShapeColor, properties.activeBorder);
            drawLayer(after.inactiveShapes.filter(shape => shape.occludeInactive),
                shape => shape.fill === maskColor ? properties.inActiveShapeColor : shape.fill, properties.inActiveBorder);
            drawLayer(after.highlightShapes, () => properties.highlightShapeColor, properties.highlightShapeBorder);
            options.onDidDrawShapes?.(after, context);
        }

        if (button) {
            button.hidden = !document.querySelector("#qa [data-occludeinactive='1']");
            button.addEventListener("click", () => { hidden = !hidden; draw(); });
        }
        if (!img.complete) img.addEventListener("load", draw, { once: true });
        sessions.set(canvas, draw);
        requestAnimationFrame(draw);
    }

    window.addEventListener("resize", () => sessions.get(document.getElementById("image-occlusion-canvas"))?.());
    window.addEventListener("keydown", event => {
        const button = document.getElementById("toggle");
        if (event.key === "M" && button && !button.hidden) button.click();
    });
    window.anki ??= {};
    window.anki.imageOcclusion = { setup, drawShape, Shape, Rectangle, Ellipse, Polygon, Text };
})();
