// TypeScript declarations for made part scripts (.part.ts).
// Adapted in part from the brepjs API shape (https://brepjs.dev, Apache-2.0).

declare module 'made' {
  export type Vec2 = [number, number] | { x: number; y: number };
  export type Vec3 = [number, number, number] | { x: number; y: number; z: number };
  export type PlaneName = 'XY' | 'XZ' | 'YZ';

  export interface PlaneSpec {
    readonly origin?: Vec3;
    readonly normal?: Vec3;
    readonly xDir?: Vec3;
    readonly xAxis?: Vec3;
    offset(distance: number): PlaneSpec;
  }

  export const Plane: {
    readonly XY: PlaneSpec;
    readonly XZ: PlaneSpec;
    readonly YZ: PlaneSpec;
    offset(plane: PlaneName | PlaneSpec, distance: number): PlaneSpec;
    custom(origin: Vec3, normal: Vec3, xAxis?: Vec3): PlaneSpec;
  };

  export function plane(base?: PlaneName | PlaneSpec, offsetDistance?: number): PlaneSpec;

  export interface ShapeNodeJSON {
    readonly kind: string;
    readonly [key: string]: unknown;
  }

  export interface Shape {
    readonly __madeShape: true;
    readonly node: ShapeNodeJSON;

    translate(offset: Vec3): Shape;
    translate(x: number, y?: number, z?: number): Shape;

    rotate(anglesDeg: Vec3): Shape;
    rotate(angleDeg: number, axis?: Vec3): Shape;
    rotateX(angleDeg: number): Shape;
    rotateY(angleDeg: number): Shape;
    rotateZ(angleDeg: number): Shape;

    scale(factor: number | Vec3): Shape;
    scale(sx: number, sy: number, sz: number): Shape;

    union(...others: Shape[]): Shape;
    fuse(...others: Shape[]): Shape;

    subtract(...others: Shape[]): Shape;
    cut(...others: Shape[]): Shape;
    difference(...others: Shape[]): Shape;

    intersect(...others: Shape[]): Shape;
    common(...others: Shape[]): Shape;
    intersection(...others: Shape[]): Shape;
  }

  export interface BoxOptions {
    width: number;
    depth: number;
    height: number;
    center?: Vec3 | boolean;
  }

  export interface CylinderOptions {
    radius?: number;
    diameter?: number;
    height: number;
    slices?: number;
    center?: Vec3 | boolean;
  }

  export interface SphereOptions {
    radius?: number;
    diameter?: number;
    slices?: number;
    center?: Vec3;
  }

  export interface ConeOptions {
    radius?: number;
    bottomRadius?: number;
    topRadius?: number;
    height: number;
    slices?: number;
    center?: Vec3 | boolean;
  }

  export function Box(width: number, depth: number, height: number, options?: { center?: Vec3 | boolean }): Shape;
  export function Box(options: BoxOptions): Shape;
  export function box(width: number, depth: number, height: number, options?: { center?: Vec3 | boolean }): Shape;
  export function box(options: BoxOptions): Shape;

  export function Cylinder(radius: number, height: number, options?: { slices?: number; center?: Vec3 | boolean }): Shape;
  export function Cylinder(options: CylinderOptions): Shape;
  export function cylinder(radius: number, height: number, options?: { slices?: number; center?: Vec3 | boolean }): Shape;
  export function cylinder(options: CylinderOptions): Shape;

  export function Sphere(radius: number, options?: { slices?: number; center?: Vec3 }): Shape;
  export function Sphere(options: SphereOptions): Shape;
  export function sphere(radius: number, options?: { slices?: number; center?: Vec3 }): Shape;
  export function sphere(options: SphereOptions): Shape;

  export function Cone(radius: number, height: number, options?: { topRadius?: number; slices?: number; center?: Vec3 | boolean }): Shape;
  export function Cone(options: ConeOptions): Shape;
  export function cone(radius: number, height: number, options?: { topRadius?: number; slices?: number; center?: Vec3 | boolean }): Shape;
  export function cone(options: ConeOptions): Shape;

  export interface ExtrudeOptions {
    height?: number;
    distance?: number;
    depth?: number;
    centered?: boolean;
  }

  export interface RevolveOptions {
    angle?: number;
    angleDegrees?: number;
    slices?: number;
  }

  export interface SketchProfile {
    readonly __madeSketch: true;
    readonly plane: PlaneSpec;
    readonly points: ReadonlyArray<[number, number]>;

    moveTo(x: number, y: number): SketchProfile;
    lineTo(x: number, y: number): SketchProfile;
    arcTo(endX: number, endY: number, radius: number, options?: { clockwise?: boolean; largeArc?: boolean; segments?: number }): SketchProfile;
    close(): SketchProfile;

    rectangle(width: number, height: number, options?: { center?: Vec2 | boolean }): SketchProfile;
    rect(width: number, height: number, options?: { center?: Vec2 | boolean }): SketchProfile;
    roundedRectangle(width: number, height: number, radius: number, options?: { detail?: number; center?: Vec2 | boolean }): SketchProfile;
    roundedRect(width: number, height: number, radius: number, options?: { detail?: number; center?: Vec2 | boolean }): SketchProfile;
    circle(radius: number, options?: { segments?: number; center?: Vec2 }): SketchProfile;
    polygon(points: ReadonlyArray<Vec2>): SketchProfile;
    regularPolygon(radius: number, sides: number, options?: { center?: Vec2 }): SketchProfile;

    translate(dx: number, dy: number): SketchProfile;
    translate(offset: Vec2): SketchProfile;

    extrude(distance: number, options?: { centered?: boolean }): Shape;
    extrude(options: ExtrudeOptions): Shape;

    revolve(angleDegrees?: number, options?: { slices?: number }): Shape;
    revolve(options: RevolveOptions): Shape;
  }

  export function Sketch(plane?: PlaneName | PlaneSpec): SketchProfile;
  export function sketch(plane?: PlaneName | PlaneSpec): SketchProfile;

  export function rectangle(width: number, height: number, options?: { plane?: PlaneName | PlaneSpec; center?: Vec2 | boolean }): SketchProfile;
  export function rect(width: number, height: number, options?: { plane?: PlaneName | PlaneSpec; center?: Vec2 | boolean }): SketchProfile;
  export function roundedRectangle(width: number, height: number, radius: number, options?: { plane?: PlaneName | PlaneSpec; detail?: number; center?: Vec2 | boolean }): SketchProfile;
  export function roundedRect(width: number, height: number, radius: number, options?: { plane?: PlaneName | PlaneSpec; detail?: number; center?: Vec2 | boolean }): SketchProfile;
  export function circle(radius: number, options?: { plane?: PlaneName | PlaneSpec; segments?: number; center?: Vec2 }): SketchProfile;
  export function polygon(points: ReadonlyArray<Vec2>, options?: { plane?: PlaneName | PlaneSpec }): SketchProfile;
  export function regularPolygon(radius: number, sides: number, options?: { plane?: PlaneName | PlaneSpec; center?: Vec2 }): SketchProfile;

  export function extrude(profile: SketchProfile, distance: number, options?: { centered?: boolean }): Shape;
  export function extrude(profile: SketchProfile, options: ExtrudeOptions): Shape;

  export function revolve(profile: SketchProfile, angleDegrees?: number, options?: { slices?: number }): Shape;
  export function revolve(profile: SketchProfile, options: RevolveOptions): Shape;

  export function union(first: Shape, ...rest: Shape[]): Shape;
  export function fuse(first: Shape, ...rest: Shape[]): Shape;

  export function subtract(base: Shape, ...tools: Shape[]): Shape;
  export function cut(base: Shape, ...tools: Shape[]): Shape;
  export function difference(base: Shape, ...tools: Shape[]): Shape;

  export function intersect(first: Shape, ...rest: Shape[]): Shape;
  export function common(first: Shape, ...rest: Shape[]): Shape;
  export function intersection(first: Shape, ...rest: Shape[]): Shape;

  export function translate(shape: Shape, offset: Vec3): Shape;
  export function translate(shape: Shape, x: number, y?: number, z?: number): Shape;

  export function rotate(shape: Shape, anglesDeg: Vec3): Shape;
  export function rotate(shape: Shape, angleDeg: number, axis?: Vec3): Shape;

  export function scale(shape: Shape, factor: number | Vec3): Shape;
  export function scale(shape: Shape, sx: number, sy: number, sz: number): Shape;

  export interface ParamOptions {
    default?: number;
    min?: number;
    max?: number;
    step?: number;
    unit?: string;
    label?: string;
  }

  export type ParamDefinition = number | ParamOptions;

  export function param(name: string, defaultValue: number, options?: Omit<ParamOptions, 'default'>): number;
  export function defineParams<T extends Record<string, ParamDefinition>>(
    schema: T
  ): { [K in keyof T]: number };

  export interface ExpectedBounds {
    min: [number, number, number];
    max: [number, number, number];
  }

  export interface ExpectedSpec {
    volume?: number;
    area?: number;
    surfaceArea?: number;
    bounds?: ExpectedBounds;
    tolerance?: number;
  }
}
