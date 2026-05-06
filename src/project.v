/*
 * Copyright (c) 2026 Steve W.
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_spacelizard_apu (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  // ------------------------------------------------------------
  // Interface
  // ------------------------------------------------------------
  // ui_in[7]   = EXEC strobe. Command runs on rising edge.
  // ui_in[6:4] = opcode
  // ui_in[3:0] = argument / RAM address
  //
  // uio_in[7:0]  = input data bus
  // uio_out[7:0] = output data bus
  // uo_out[7:0]  = live A register output

  wire exec = ui_in[7];
  wire [2:0] opcode = ui_in[6:4];
  wire [3:0] arg    = ui_in[3:0];

  reg exec_d;

  wire exec_rise = exec & ~exec_d;

  // ------------------------------------------------------------
  // APU state
  // ------------------------------------------------------------

  reg [7:0] A;
  reg [7:0] B;

  reg flag_z;  // zero
  reg flag_c;  // carry / not-borrow
  reg flag_n;  // negative
  reg flag_v;  // overflow

  reg [7:0] ram [0:15];

  integer i;

  // ------------------------------------------------------------
  // ALU helper wires
  // ------------------------------------------------------------

  wire [8:0] add_b = {1'b0, A} + {1'b0, B};
  wire [8:0] add_d = {1'b0, A} + {1'b0, uio_in};

  wire [8:0] sub_b = {1'b0, A} - {1'b0, B};
  wire [8:0] sub_d = {1'b0, A} - {1'b0, uio_in};

  wire ov_add_b = ~(A[7] ^ B[7])      & (A[7] ^ add_b[7]);
  wire ov_add_d = ~(A[7] ^ uio_in[7]) & (A[7] ^ add_d[7]);

  wire ov_sub_b =  (A[7] ^ B[7])      & (A[7] ^ sub_b[7]);
  wire ov_sub_d =  (A[7] ^ uio_in[7]) & (A[7] ^ sub_d[7]);

  // ------------------------------------------------------------
  // Main sequential logic
  // ------------------------------------------------------------

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      exec_d <= 1'b0;

      A <= 8'h00;
      B <= 8'h00;

      flag_z <= 1'b1;
      flag_c <= 1'b0;
      flag_n <= 1'b0;
      flag_v <= 1'b0;

      // ---RAM RESET removed to save routing area---
      // for (i = 0; i < 16; i = i + 1) begin
      //   ram[i] <= 8'h00;
      // end
    end else begin
      exec_d <= exec;

      if (ena && exec_rise) begin
        case (opcode)

          // ----------------------------------------------------
          // 000: load / move
          // ----------------------------------------------------
          // arg 0: A = uio_in
          // arg 1: B = uio_in
          // arg 2: A = B
          // arg 3: B = A
          // arg 4: clear A
          // arg 5: clear B
          3'b000: begin
            case (arg)
              4'h0: A <= uio_in;
              4'h1: B <= uio_in;
              4'h2: A <= B;
              4'h3: B <= A;
              4'h4: A <= 8'h00;
              4'h5: B <= 8'h00;
              default: begin end
            endcase

            flag_c <= 1'b0;
            flag_v <= 1'b0;
          end

          // ----------------------------------------------------
          // 001: arithmetic
          // ----------------------------------------------------
          // arg 0: A = A + B
          // arg 1: A = A + uio_in
          // arg 2: A = A - B
          // arg 3: A = A - uio_in
          3'b001: begin
            case (arg)
              4'h0: begin
                A <= add_b[7:0];
                flag_z <= (add_b[7:0] == 8'h00);
                flag_n <= add_b[7];
                flag_c <= add_b[8];
                flag_v <= ov_add_b;
              end

              4'h1: begin
                A <= add_d[7:0];
                flag_z <= (add_d[7:0] == 8'h00);
                flag_n <= add_d[7];
                flag_c <= add_d[8];
                flag_v <= ov_add_d;
              end

              4'h2: begin
                A <= sub_b[7:0];
                flag_z <= (sub_b[7:0] == 8'h00);
                flag_n <= sub_b[7];
                flag_c <= ~sub_b[8];  // 1 = no borrow
                flag_v <= ov_sub_b;
              end

              4'h3: begin
                A <= sub_d[7:0];
                flag_z <= (sub_d[7:0] == 8'h00);
                flag_n <= sub_d[7];
                flag_c <= ~sub_d[8];  // 1 = no borrow
                flag_v <= ov_sub_d;
              end

              default: begin end
            endcase
          end

          // ----------------------------------------------------
          // 010: logic
          // ----------------------------------------------------
          // arg 0: A = A & B
          // arg 1: A = A | B
          // arg 2: A = A ^ B
          // arg 3: A = ~A
          // arg 4: A = A & uio_in
          // arg 5: A = A | uio_in
          // arg 6: A = A ^ uio_in
          3'b010: begin
            case (arg)
              4'h0: A <= A & B;
              4'h1: A <= A | B;
              4'h2: A <= A ^ B;
              4'h3: A <= ~A;
              4'h4: A <= A & uio_in;
              4'h5: A <= A | uio_in;
              4'h6: A <= A ^ uio_in;
              default: begin end
            endcase

            flag_c <= 1'b0;
            flag_v <= 1'b0;
          end

          // ----------------------------------------------------
          // 011: shifts / rotates
          // ----------------------------------------------------
          // arg 0: A = A << 1
          // arg 1: A = A >> 1
          // arg 2: rotate left
          // arg 3: rotate right
          3'b011: begin
            case (arg)
              4'h0: begin
                flag_c <= A[7];
                A <= {A[6:0], 1'b0};
              end

              4'h1: begin
                flag_c <= A[0];
                A <= {1'b0, A[7:1]};
              end

              4'h2: begin
                flag_c <= A[7];
                A <= {A[6:0], A[7]};
              end

              4'h3: begin
                flag_c <= A[0];
                A <= {A[0], A[7:1]};
              end

              default: begin end
            endcase

            flag_v <= 1'b0;
          end

          // ----------------------------------------------------
          // 100: RAM write
          // ----------------------------------------------------
          // ram[arg] = uio_in
          3'b100: begin
            ram[arg] <= uio_in;
          end

          // ----------------------------------------------------
          // 101: RAM read into A
          // ----------------------------------------------------
          // A = ram[arg]
          3'b101: begin
            A <= ram[arg];
            flag_z <= (ram[arg] == 8'h00);
            flag_n <= ram[arg][7];
            flag_c <= 1'b0;
            flag_v <= 1'b0;
          end

          default: begin end

        endcase
      end
    end
  end

  // ------------------------------------------------------------
  // Output bus
  // ------------------------------------------------------------

  assign uo_out = A;

  // opcode 110: read registers/status
  //   arg 0 = A
  //   arg 1 = B
  //   arg 2 = flags: {0000, V, N, C, Z}
  //
  // opcode 111: read RAM[arg]

  assign uio_oe = (opcode == 3'b110 || opcode == 3'b111) ? 8'hff : 8'h00;

  assign uio_out =
    (opcode == 3'b110 && arg == 4'h0) ? A :
    (opcode == 3'b110 && arg == 4'h1) ? B :
    (opcode == 3'b110 && arg == 4'h2) ? {4'b0000, flag_v, flag_n, flag_c, flag_z} :
    (opcode == 3'b111)                ? ram[arg] :
                                         8'h00;

endmodule
