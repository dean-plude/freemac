// SPDX-License-Identifier: GPL-3.0-or-later
// The library half of the cxx_exceptions test (see shapes.h).
#include "shapes.h"

Shape::~Shape() {}

std::string Square::name() const { return "square"; }
double Square::area() const { return side * side; }

struct Circle : Shape {
    double r;
    explicit Circle(double radius) : r(radius) {}
    std::string name() const override { return "circle"; }
    double area() const override { return 3.0 * r * r; }
};

Shape *make_shape(const std::string &kind, double size)
{
    if (kind == "square")
        return new Square(size);
    if (kind == "circle")
        return new Circle(size);
    throw BadShape("no shape called " + kind, 7);
}

void check_shape(const Shape *s)
{
    if (!s)
        throw std::invalid_argument("no shape");
}

const std::type_info &square_type() { return typeid(Square); }
