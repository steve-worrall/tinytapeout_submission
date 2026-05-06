# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


async def exec_cmd(dut, opcode, arg, data=0):
    dut.uio_in.value = data
    dut.ui_in.value = 0x80 | ((opcode & 0x7) << 4) | (arg & 0xF)
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = ((opcode & 0x7) << 4) | (arg & 0xF)
    await ClockCycles(dut.clk, 1)


async def reset(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


def flags_value(dut):
    return int(dut.uio_out.value)


async def read_flags(dut):
    dut.ui_in.value = (0b110 << 4) | 0x2
    await ClockCycles(dut.clk, 1)
    return flags_value(dut)


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start expanded APU test")

    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    await reset(dut)

    # -------------------------
    # Basic load/add/xor/RAM
    # -------------------------

    await exec_cmd(dut, 0b000, 0x0, 0x12)  # A = 0x12
    assert int(dut.uo_out.value) == 0x12

    await exec_cmd(dut, 0b000, 0x1, 0x03)  # B = 0x03

    await exec_cmd(dut, 0b001, 0x0)        # A = A + B
    assert int(dut.uo_out.value) == 0x15

    await exec_cmd(dut, 0b010, 0x2)        # A = A XOR B
    assert int(dut.uo_out.value) == 0x16

    await exec_cmd(dut, 0b100, 0x4, 0xAB)  # RAM[4] = 0xAB
    await exec_cmd(dut, 0b101, 0x4)        # A = RAM[4]
    assert int(dut.uo_out.value) == 0xAB

    # -------------------------
    # Subtract
    # -------------------------

    await exec_cmd(dut, 0b000, 0x0, 0x10)  # A = 0x10
    await exec_cmd(dut, 0b000, 0x1, 0x04)  # B = 0x04
    await exec_cmd(dut, 0b001, 0x2)        # A = A - B
    assert int(dut.uo_out.value) == 0x0C

    flags = await read_flags(dut)
    assert flags & 0x2                      # C = 1, no borrow

    # -------------------------
    # Zero flag
    # -------------------------

    await exec_cmd(dut, 0b000, 0x0, 0x55)  # A = 0x55
    await exec_cmd(dut, 0b000, 0x1, 0x55)  # B = 0x55
    await exec_cmd(dut, 0b001, 0x2)        # A = A - B = 0
    assert int(dut.uo_out.value) == 0x00

    flags = await read_flags(dut)
    assert flags & 0x1                      # Z = 1

    # -------------------------
    # Carry on addition
    # -------------------------

    await exec_cmd(dut, 0b000, 0x0, 0xFF)  # A = 0xFF
    await exec_cmd(dut, 0b000, 0x1, 0x01)  # B = 0x01
    await exec_cmd(dut, 0b001, 0x0)        # A = A + B = 0x00 carry
    assert int(dut.uo_out.value) == 0x00

    flags = await read_flags(dut)
    assert flags & 0x1                      # Z = 1
    assert flags & 0x2                      # C = 1

    # -------------------------
    # Negative flag
    # -------------------------

    await exec_cmd(dut, 0b000, 0x0, 0x7F)
    await exec_cmd(dut, 0b001, 0x1, 0x01)  # A = A + 1 = 0x80
    assert int(dut.uo_out.value) == 0x80

    flags = await read_flags(dut)
    assert flags & 0x4                      # N = 1

    # -------------------------
    # Overflow flag
    # 0x7F + 0x01 = 0x80 signed overflow
    # -------------------------

    assert flags & 0x8                      # V = 1

    # -------------------------
    # Shifts
    # -------------------------

    await exec_cmd(dut, 0b000, 0x0, 0x81)  # A = 1000_0001
    await exec_cmd(dut, 0b011, 0x0)        # shift left => 0x02, C=1
    assert int(dut.uo_out.value) == 0x02

    flags = await read_flags(dut)
    assert flags & 0x2                      # C = 1

    await exec_cmd(dut, 0b011, 0x1)        # shift right => 0x01, C=0
    assert int(dut.uo_out.value) == 0x01

    # -------------------------
    # Direct RAM read on uio_out
    # opcode 111 outputs RAM[arg]
    # -------------------------

    await exec_cmd(dut, 0b100, 0xA, 0x5C)  # RAM[10] = 0x5C

    dut.ui_in.value = (0b111 << 4) | 0xA
    await ClockCycles(dut.clk, 1)

    assert int(dut.uio_out.value) == 0x5C
    assert int(dut.uio_oe.value) == 0xFF

    dut._log.info("Expanded APU test passed")