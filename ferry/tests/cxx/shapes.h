// SPDX-License-Identifier: GPL-3.0-or-later
// A C++ class hierarchy shared by a Mac library (shapes.cpp) and the
// program that uses it (exceptions.cpp): typeinfo, virtual calls and
// exceptions across the two images.
#pragma once
#include <stdexcept>
#include <string>

struct Shape {
    virtual ~Shape();
    virtual std::string name() const = 0;
    virtual double area() const = 0;
};

struct Square : Shape {
    double side;
    explicit Square(double s) : side(s) {}
    std::string name() const override;
    double area() const override;
};

struct BadShape : std::runtime_error {
    int code;
    BadShape(const std::string &what, int c) : std::runtime_error(what), code(c) {}
};

Shape *make_shape(const std::string &kind, double size);   // throws BadShape for an unknown kind
void check_shape(const Shape *s);                          // throws std::invalid_argument for a nil shape
const std::type_info &square_type();
