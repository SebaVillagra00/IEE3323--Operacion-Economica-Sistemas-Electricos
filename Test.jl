using DataFrames, CSV

#= using JuMP , HiGHS
model=Model(HiGHS.Optimizer)
@variable(model,x>=0)
@variable(model, 0 <= y <= 3)
@objective(model, Min, 12x + 20y)
@constraint(model, c1, 6x + 8y >= 100)
@constraint(model, c2, 7x +12y >=120)
print(model)
optimize!(model)
termination_status(model)
primal_status(model)
dual_status(model)
objective_value(model)
value(x)
value(y)
shadow_price(c1) =#
# Elimine shadow_price(c2)

## revisar performance Tips en la página de julia ---> se recomienda typing (definir tipos)  ->> utilizar for  --> el signo de exclamación en un afunción modifica el input 


# Estoy agregando unas lineas
println("Prueba de lectura de datos")

###esta


generators_ref = CSV.File("Generators.csv") |> DataFrame 
generators = copy(generators_ref)
println("A continuación se muestran los datos")
show(generators)
