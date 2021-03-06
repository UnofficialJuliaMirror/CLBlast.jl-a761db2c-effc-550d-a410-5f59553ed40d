
@compat for (func, elty) in [(:CLBlastSgemv, Float32), (:CLBlastDgemv, Float64),
                     (:CLBlastCgemv, ComplexF32), (:CLBlastZgemv, ComplexF64)]
    #TODO: (:CLBlastHgemv, Float16)

    @eval function $func(layout::CLBlastLayout, a_transpose::CLBlastTranspose,
                         m::Integer, n::Integer,
                         alpha::$elty,
                         a_buffer::cl.CL_mem, a_offset::Integer, a_ld::Integer,
                         x_buffer::cl.CL_mem, x_offset::Integer, x_inc::Integer,
                         beta::$elty,
                         y_buffer::cl.CL_mem, y_offset::Integer, y_inc::Integer,
                         queue::cl.CmdQueue, event::cl.Event)
        err = ccall(
            ($(string(func)), libCLBlast),
            cl.CL_int,
            (Cint, Cint, Csize_t, Csize_t, $elty, Ptr{Cvoid}, Csize_t, Csize_t, Ptr{Cvoid}, Csize_t, Csize_t,
              $elty, Ptr{Cvoid}, Csize_t, Csize_t, Ptr{Cvoid}, Ptr{Cvoid}),
            Cint(layout), Cint(a_transpose), m, n, alpha, a_buffer, a_offset, a_ld, x_buffer, x_offset, x_inc,
              beta, y_buffer, y_offset, y_inc, Ref(queue), Ref(event)
        )
        if err != cl.CL_SUCCESS
            println(stderr, "Calling function $(string($func)) failed!")
            throw(CLBlastError(err))
        end
        return err
    end

    @eval function gemv!(tA::Char, α::Number, A::cl.CLArray{$elty,2},
                         x::cl.CLArray{$elty}, β::Number, y::cl.CLArray{$elty};
                         queue::cl.CmdQueue=cl.queue(y))
        # check and convert arguments
        m, n = size(A)
        if tA == 'N'
            a_transpose = CLBlastTransposeNo
            if length(x) != n || length(y) != m
                throw(DimensionMismatch("A has dimensions $(size(A)), x has length $(length(x)) and y has length $(length(y))."))
            end
        elseif tA == 'T' || (tA == 'C' && $elty <: Real)
            a_transpose = CLBlastTransposeYes
            if length(x) != m || length(y) != n
                throw(DimensionMismatch("The adjoint of A has dimensions $n, $m, x has length $(length(x)) and y has length $(length(y))"))
            end
        elseif tA == 'C' && $elty <: Complex
            a_transpose = CLBlastTransposeConjugate
            if length(x) != m || length(y) != n
                throw(DimensionMismatch("The transpose of A has dimensions $n, $m, x has length $(length(x)) and y has length $(length(y))."))
            end
        else
            throw(ArgumentError("Transpose marker `tA` is $(tA) but only 'N', 'T', and 'C' are allowed."))
        end
        alpha = convert($elty, α)
        beta  = convert($elty, β)
        layout = CLBlastLayoutColMajor

        # output event
        event::cl.Event = cl.Event(C_NULL)

        $func(layout, a_transpose,
              m, n,
              alpha,
              pointer(A), 0, size(A,1),
              pointer(x), 0, 1,
              beta,
              pointer(y), 0, 1,
              queue, event)

        # wait for kernel
        cl.wait(event)

        y
    end

end
