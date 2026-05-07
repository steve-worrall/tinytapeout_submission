/*
 * Copyright (c) 2026 Steve W.
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_spacelizard_apu (
  input  wire [7:0] ui_in,          // 8-bit input control bus
  output wire [7:0] uo_out,         // 8-bit output for A register
  input  wire [7:0] uio_in,         // 8-bit bidirectional input data bus
  output wire [7:0] uio_out,        // 8-bit bidirectional output data bus
  output wire [7:0] uio_oe,         // output enable for bidirectional bus
  input  wire       ena,            // module enable signal
  input  wire       clk,            // system clock
  input  wire       rst_n           // active-low reset
);

  // Interface
  wire exec = ui_in[7];             // execute strobe signal (bit 7)
  wire [2:0] opcode = ui_in[6:4];   // operation code (bits 6-4)
  wire [3:0] arg    = ui_in[3:0];   // argument / RAM address (bits 3-0)
  wire [2:0] ram_addr = arg[2:0];   // extract RAM address from lower 3 bits

  reg exec_d;                       // delayed execute signal for edge detection

  wire exec_rise = exec & ~exec_d;  // rising edge detector for execute

  // APU state
  reg [7:0] A;                      // accumulator register
  reg [7:0] B;                      // B operand register

  reg flag_z;                       // zero flag
  reg flag_c;                       // carry / not-borrow flag
  reg flag_n;                       // negative flag
  reg flag_v;                       // overflow flag

  reg [7:0] ram [0:7];              // 8x8 RAM array

  // ALU helper wires
  wire [8:0] add_b = {1'b0, A} + {1'b0, B};                 // 9-bit result of A + B
  wire [8:0] add_d = {1'b0, A} + {1'b0, uio_in};            // 9-bit result of A + data input

  wire [8:0] sub_b = {1'b0, A} - {1'b0, B};                 // 9-bit result of A - B
  wire [8:0] sub_d = {1'b0, A} - {1'b0, uio_in};            // 9-bit result of A - data input

  wire ov_add_b = ~(A[7] ^ B[7])      & (A[7] ^ add_b[7]);  // overflow detection for A+B
  wire ov_add_d = ~(A[7] ^ uio_in[7]) & (A[7] ^ add_d[7]);  // overflow detection for A+data

  wire ov_sub_b =  (A[7] ^ B[7])      & (A[7] ^ sub_b[7]);  // overflow detection for A-B
  wire ov_sub_d =  (A[7] ^ uio_in[7]) & (A[7] ^ sub_d[7]);  // overflow detection for A-data

  // Main sequential logic
  always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin                 // reset on active-low rst_n
    exec_d <= 1'b0;                 // clear delayed execute signal

    A <= 8'h00;                     // clear accumulator
    B <= 8'h00;                     // clear B register

    flag_z <= 1'b1;                 // set zero flag (A=0)
    flag_c <= 1'b0;                 // clear carry flag
    flag_n <= 1'b0;                 // clear negative flag
    flag_v <= 1'b0;                 // clear overflow flag

  end else begin
    exec_d <= exec;                 // capture current execute for edge detection

    if (ena && exec_rise) begin     // execute on rising edge when enabled
    case (opcode)                   // decode operation

      3'b000: begin                 // load/move operations
      case (arg)
        4'h0: A <= uio_in;          // load A from data input
        4'h1: B <= uio_in;          // load B from data input
        4'h2: A <= B;               // copy B to A
        4'h3: B <= A;               // copy A to B
        4'h4: A <= 8'h00;           // clear A
        4'h5: B <= 8'h00;           // clear B
        default: begin end
      endcase

      flag_c <= 1'b0;               // clear carry
      flag_v <= 1'b0;               // clear overflow
      end

      3'b001: begin                       // arithmetic operations
      case (arg)
        4'h0: begin                       // A = A + B
        A <= add_b[7:0];                  // store result
        flag_z <= (add_b[7:0] == 8'h00);  // set zero flag
        flag_n <= add_b[7];               // set negative flag from MSB
        flag_c <= add_b[8];               // set carry flag from overflow bit
        flag_v <= ov_add_b;               // set overflow flag
        end

        4'h1: begin                       // A = A + data input
        A <= add_d[7:0];                  // store result
        flag_z <= (add_d[7:0] == 8'h00);  // set zero flag
        flag_n <= add_d[7];               // set negative flag
        flag_c <= add_d[8];               // set carry flag
        flag_v <= ov_add_d;               // set overflow flag
        end

        4'h2: begin                       // A = A - B
        A <= sub_b[7:0];                  // store result
        flag_z <= (sub_b[7:0] == 8'h00);  // set zero flag
        flag_n <= sub_b[7];               // set negative flag
        flag_c <= ~sub_b[8];              // set carry (1 = no borrow)
        flag_v <= ov_sub_b;               // set overflow flag
        end

        4'h3: begin                       // A = A - data input
        A <= sub_d[7:0];                  // store result
        flag_z <= (sub_d[7:0] == 8'h00);  // set zero flag
        flag_n <= sub_d[7];               // set negative flag
        flag_c <= ~sub_d[8];              // set carry (1 = no borrow)
        flag_v <= ov_sub_d;               // set overflow flag
        end

        default: begin end
      endcase
      end

      3'b010: begin  // logical operations
      case (arg)
        4'h0: A <= A & B;                 // A = A AND B
        4'h1: A <= A | B;                 // A = A OR B
        4'h2: A <= A ^ B;                 // A = A XOR B
        4'h3: A <= ~A;                    // A = NOT A
        4'h4: A <= A & uio_in;            // A = A AND data input
        4'h5: A <= A | uio_in;            // A = A OR data input
        4'h6: A <= A ^ uio_in;            // A = A XOR data input
        default: begin end
      endcase

      flag_c <= 1'b0;                     // clear carry
      flag_v <= 1'b0;                     // clear overflow
      end

      3'b011: begin  // shift and rotate operations
      case (arg)
        4'h0: begin                     // shift A left by 1
        flag_c <= A[7];                   // capture MSB to carry
        A <= {A[6:0], 1'b0};              // shift and fill with 0
        end

        4'h1: begin                     // shift A right by 1
        flag_c <= A[0];                   // capture LSB to carry
        A <= {1'b0, A[7:1]};              // shift and fill with 0
        end

        4'h2: begin                     // rotate A left
        flag_c <= A[7];                   // capture MSB to carry
        A <= {A[6:0], A[7]};              // rotate MSB to LSB
        end

        4'h3: begin                     // rotate A right
        flag_c <= A[0];                   // capture LSB to carry
        A <= {A[0], A[7:1]};              // rotate LSB to MSB
        end

        default: begin end
      endcase

      flag_v <= 1'b0;                   // clear overflow
      end

      3'b100: begin                     // RAM write operation
      ram[ram_addr] <= uio_in;            // write data input to RAM at address
      end

      3'b101: begin                     // RAM read into A
      A <= ram[ram_addr];                   // load RAM value into A
      flag_z <= (ram[ram_addr] == 8'h00);   // set zero flag
      flag_n <= ram[ram_addr][7];           // set negative flag
      flag_c <= 1'b0;                       // clear carry
      flag_v <= 1'b0;                       // clear overflow
      end

      default: begin end

    endcase
    end
  end
  end

  // Output bus
  assign uo_out = A;                                                        // output A register on main output

  assign uio_oe = (opcode == 3'b110 || opcode == 3'b111) ? 8'hff : 8'h00;   // enable tristate output for read operations

  assign uio_out =                                                          // multiplex register/RAM reads to output
  (opcode == 3'b110 && arg == 4'h0) ? A :                                           // output A for read register opcode
  (opcode == 3'b110 && arg == 4'h1) ? B :                                           // output B for read register opcode
  (opcode == 3'b110 && arg == 4'h2) ? {4'b0000, flag_v, flag_n, flag_c, flag_z} :   // output flags
  (opcode == 3'b111)                ? ram[ram_addr] :                               // output RAM value for read opcode
                     8'h00;                                                         // default to 0

endmodule
