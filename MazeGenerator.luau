-- Maze Generator Application

--[[ Maze type, I decided to make the maze OOP as I believed it would have been easier to treat it as an object and add functionality onto it,
It seems as I was right later on, I have only used OOP twice so I really thought it was gonna be useful. It has all the Info I think would be
needed outside of its scope, a.k.a used everyone in the script with the self : Maze being passed. ]]
export type Maze = typeof(setmetatable({} :: {
	OriginPosition : Vector3, -- The Position the maze should be created from or the first cell(0,0) should be placed.
	GridSize : number, -- Grid Dimensions like 10x10, 20x20, Maze is always a Square so it is just a number.
	MazeFolder : Folder?, -- A reference to the folder that holds all the Cells in the Maze
	Cells : {string : Cell}?, -- A table that holds all the Cells in the Maze and their information like Direction and Whether it is Visited
	OriginCell : string?, -- Fun fact it was previously OriginNode, as I was using the reference of the OriginShift video while creating that algorithm
	NonVisitedCells : {string}? -- I decided to make it a part of the object so I didn't need to pass over the table in a function, so if a Cell is not inside Ik it is visited, if it is ik it isn't visited
}, MazeGenerator))

type Cell = {Direction : string, Visited : boolean} -- I needed Direction value so that when updating the maze it can adjust the celss depending on its direction.
type AStarCellInfo = { Fcost : number?, Gcost : number?, Hcost : number?, Origin : string?, PathDistance : number?, Closed : boolean, Start : boolean? } -- According to the A* algorithm, I only needed those values, tbh idk the point of pathdistance.

local MazeGenerator = {}
MazeGenerator.__index = MazeGenerator -- OOP

local CellSize = 8 -- I plan to add the ability to change the actual size of the maze, rn all cells are 8x8, don't mistaken for the Grid
local Cell = game:GetService("ReplicatedStorage"):WaitForChild("Cell") -- Reference to the Cell Instance

local FloorColor = Color3.new(1, 1, 1) -- Default Cell Floor Colour, incase I wanted to change it for whatsoever reason
local WallColor = Color3.fromHex("#1b2a35") -- Defauly Wall Colour, vice versa

local function AbbreviateDir(Direction : string) -- I earlier only used "S","N","W","E" to show direction then randomly one of my functions uses the full name so I had to add a way to convert it back.
	return string.split(Direction, "")[1] -- splits string so West, {"W", "E", "S", "T"} then return the first Letter "W"
end

local function UnAbbreviateDir(Direction : string) -- Opposite of the top,
	local Dirs = {["N"] = "North", ["W"] = "West", ["S"] = "South", ["E"] = "East"}
	if not Dirs[Direction] then return false end
	return Dirs[Direction]
end

local function ChangeWallColor(Cell : Model, Color : Color3) -- A Simple function for changing a cell wall colour
	for _, Wall in Cell:GetChildren() do
		if Wall.Name ~= "Floor" or Wall.Name ~= "Middle" then
			Wall.Color = Color
		end
	end
end

local function ChangeCellFloorColor(self : Maze, Cell : string, Color : Color3) -- A Simple function that changes the floor colour, why did I call it color I blame roblox and their american naming
	self.MazeFolder[Cell].Middle.Color = Color
end

local function ChangeToOrigin(Cell : Model) -- It Changed a cell to an OriginNode, was used in the past as a way of resseting the Maze or showing a cell as without direction, but I don't use it again, tho maybe later
	for _, Wall : BasePart in Cell:GetChildren() do
		if Wall.Name ~= "Floor" or Wall.Name ~= "Middle" then
			Wall.Transparency = 0
			Wall.CanCollide = true
		end
	end
	Cell.Middle.Color = Color3.new(1, 0, 0)
end

local function CoordToTable(Coord : string) : {x : number, z : number} -- Turns The Coords I name cells "0,1" to a table {x = 0, z = 1}
	local Split = string.split(Coord, ",")
	local CoordTable = {x = Split[1], z = Split[2]}
	return CoordTable
end --  I just realised I should have converted tonumber(), this why --!strict is useful, this caused me errors later on cause it was a string

local function OppositeDirection(Direction : string)
	if Direction == "N" then return "S" end
	if Direction == "S" then return "N" end
	if Direction == "E" then return "W" end
	if Direction == "W" then return "E" end
end

local function GetNeighbourCells(self : Maze, Coord : string) -- Gets all the reference of a Cell's neighbour in the maze folder that holds all physical cells.
	local NeighbourCells = {}

	local MazeFolder = self.MazeFolder
	local CoordTable = CoordToTable(Coord)

	NeighbourCells.North = MazeFolder:FindFirstChild(CoordTable.x..","..(CoordTable.z - 1)) -- The Z-Axis is Vertical from 0 - Gridsize, so z-axis - 1 would be above the Cell being North.
	NeighbourCells.East = MazeFolder:FindFirstChild((CoordTable.x + 1)..","..CoordTable.z) -- The X-Axis is Horizontal from 0 - Gridsize, so x-axis + 1 would be "infront" of the cell to the East.
	NeighbourCells.South = MazeFolder:FindFirstChild(CoordTable.x..","..(CoordTable.z + 1))
	NeighbourCells.West = MazeFolder:FindFirstChild((CoordTable.x - 1)..","..CoordTable.z)

	return NeighbourCells
end

local function GetNeighbourCoords(self : Maze, Coord : string) -- Gets all the neighbour Coords, and set nil to the impossible ones
	local NeighbourCells = {}

	local MazeFolder = self.MazeFolder
	local CoordTable = CoordToTable(Coord)

	NeighbourCells.North = CoordTable.x..","..(CoordTable.z - 1)
	NeighbourCells.East = (CoordTable.x + 1)..","..CoordTable.z
	NeighbourCells.South = CoordTable.x..","..(CoordTable.z + 1)
	NeighbourCells.West = (CoordTable.x - 1)..","..CoordTable.z

	if CoordTable.z - 1 < 0 then NeighbourCells.North = nil end -- Can't be less than zero so it doesn't exist
	if CoordTable.z + 1 > self.GridSize then NeighbourCells.South = nil end -- Can't be more than the Gridsize do it doesn't exist
	if CoordTable.x - 1 < 0 then NeighbourCells.West = nil end 
	if CoordTable.x + 1 > self.GridSize then NeighbourCells.East = nil end

	return NeighbourCells
end

local function GetCellFromDirection(self : Maze, Coord : string, Direction : string) -- Returns the Neighbour Coords with their direction as indexes in a table.
	local NeighbourCells = {}

	local CoordTable = CoordToTable(Coord)

	NeighbourCells.N = CoordTable.x..","..(CoordTable.z - 1)
	NeighbourCells.E = (CoordTable.x + 1)..","..CoordTable.z
	NeighbourCells.S = CoordTable.x..","..(CoordTable.z + 1)
	NeighbourCells.W = (CoordTable.x - 1)..","..CoordTable.z

	return NeighbourCells[Direction]
end

--[[ So to visual represent they maze, I save the maze state in a table using a Direction variable to show which direction it opens too, then I loop through all the cells in the table and update their state
this ChangeCellDirection is responsible in making those pyhsical changes to cell like opening up walls]]--
local function ChangeCellDirection(self : Maze, Coord : string, Direction : string) 
	local Cell = self.MazeFolder:FindFirstChild(Coord)
	
	if Direction == "I" then -- Later on I added a direction called "I" meaning Ignore as it used to just set a directionless cell to origin even tho it wasn't meant to, which didn't work for other algorithms that didin't have a default direction like origin shift
		return
	elseif UnAbbreviateDir(Direction) then
		Direction = UnAbbreviateDir(Direction)
		Cell[Direction].Transparency = 1
		Cell[Direction].CanCollide = 1
		
		local CoordTable = CoordToTable(Coord)
		-- So earlier on met a problem where they wall will still be their realised that I have to also remove the neighbour opposite walls
		local NextCell = self.MazeFolder:FindFirstChild(GetCellFromDirection(self, Coord, AbbreviateDir(Direction)))
		NextCell[UnAbbreviateDir(OppositeDirection(AbbreviateDir(Direction)))].Transparency = 1 -- Opposite of East being West
		NextCell[UnAbbreviateDir(OppositeDirection(AbbreviateDir(Direction)))].CanCollide = false
	else
		ChangeToOrigin(Cell)
	end
end

local function UpdateCell(self : Maze, Coord : string, Direction : string) -- Deals with updating the cell and neighbour cells
	local Cell = self.MazeFolder:FindFirstChild(Coord)
	local NeighbourCells = GetNeighbourCells(self, Coord)
	ChangeCellDirection(self, Coord, Direction)
	
	if NeighbourCells[UnAbbreviateDir(Direction)] and self.Cells[NeighbourCells[UnAbbreviateDir(Direction)]] == OppositeDirection(Direction) then ChangeCellDirection(self, Coord, Direction) end
end

local function UpdateMazeWithCells(self : Maze, Cells : {string : Cell}) -- Loop that updates the maze
	local MazeFolder = self.MazeFolder

	for Coord, Cell in Cells do
		UpdateCell(self, Coord, Cell.Direction)
	end
end

local function RandomPossibleDirection(self : Maze, Coord : string) -- Gets a random possible direction, so any direction that isn't out of bounds.
	local PossibleNeighbours = {}

	local CoordTable = CoordToTable(Coord)

	if self.MazeFolder:FindFirstChild(CoordTable.x..","..(CoordTable.z - 1)) then table.insert(PossibleNeighbours, "N") end -- adds to a table
	if self.MazeFolder:FindFirstChild((CoordTable.x + 1)..","..CoordTable.z) then table.insert(PossibleNeighbours, "E") end
	if self.MazeFolder:FindFirstChild(CoordTable.x..","..(CoordTable.z + 1)) then table.insert(PossibleNeighbours, "S") end
	if self.MazeFolder:FindFirstChild((CoordTable.x - 1)..","..CoordTable.z) then table.insert(PossibleNeighbours, "W") end

	local RandomDirection = PossibleNeighbours[math.random(1, table.maxn(PossibleNeighbours))] -- get a random number between 1 and the amount of items in the table, then uses that as an index.

	return RandomDirection
end

local function RandomPossibleNotVisitedDirection(self : Maze, Coord : string) -- Gets a RandomPossible Direction, but filters out the ones that are already visited.
	local PossibleNeighbours = {}

	local CoordTable = CoordToTable(Coord)

	--[[Checks whether it is in NonvisitedCells table and if so insert, if not then skip. I could have also used self.Nodes[CoordTable.x..","..(CoordTable.z - 1)].Visited instead tbh that would be faster instead
	of searching through a table, promise I would change it]]-- 
	if self.MazeFolder:FindFirstChild(CoordTable.x..","..(CoordTable.z - 1)) and table.find(self.NonVisitedCells, CoordTable.x..","..(CoordTable.z - 1)) then table.insert(PossibleNeighbours, "N") end
	if self.MazeFolder:FindFirstChild((CoordTable.x + 1)..","..CoordTable.z) and table.find(self.NonVisitedCells, (CoordTable.x + 1)..","..CoordTable.z) then table.insert(PossibleNeighbours, "E") end
	if self.MazeFolder:FindFirstChild(CoordTable.x..","..(CoordTable.z + 1)) and table.find(self.NonVisitedCells, CoordTable.x..","..(CoordTable.z + 1)) then table.insert(PossibleNeighbours, "S") end
	if self.MazeFolder:FindFirstChild((CoordTable.x - 1)..","..CoordTable.z) and table.find(self.NonVisitedCells, (CoordTable.x - 1)..","..CoordTable.z) then table.insert(PossibleNeighbours, "W") end

	local Size = table.maxn(PossibleNeighbours)
	if Size < 1 then return end -- Possible for all surrounding neighbours to be visited, so it returns nil this is used in the wilson algorithm I believe.

	local RandomDirection = PossibleNeighbours[math.random(1, Size)]

	return RandomDirection
end

local function CoordToCell(self : Maze, Coord : string) -- Gets the physical Cell Model reference from a Coordinate ex. ("1,2")
	return self.MazeFolder:FindFirstChild(Coord)
end

--[=[
	Gets Coords of a Random Not Visited Cell
	was testing roblox function descirption
]=]
 --[[So code was much smaller than this but had a week long problem that stopped the wilson algorithm from working just to realise that this function was returning visited cells for some reason.
It used the roblox search feature, and tracked down every instance of adding to nonvisited table and still couldn't figure out why it would be in the nonvisited table and .Visited would be true.]]--
local function GetRandomNotVisitedCell(self : Maze)
	--[[Does a loop until it finds a nonvisited Cell that also has .visited as false and removed any that don't, fixing the problem, after doing this the wilson algorithm I gave up on actually worked, 
		they amount of time I spent debugging it was more than coding pratically all the algorithms]]--
	while #self.NonVisitedCells > 0 do
		local index = math.random(1, #self.NonVisitedCells)
		local cell = self.NonVisitedCells[index]

		if not self.Cells[cell].Visited then
			return cell -- , index if you also want the index
		else
			table.remove(self.NonVisitedCells, index)
		end
	end
	return
end

local function SetCellToVisited(self : Maze, Cell : string)
	self.Cells[Cell].Visited = true
	table.remove(self.NonVisitedCells, table.find(self.NonVisitedCells, Cell))
	--self.MazeFolder:FindFirstChild(Cell).Middle.Transparency = 1 was used for visual feedback now I just use colors instead of empty
end

local function SetCellToNotVisited(self : Maze, Cell : string)
	self.Cells[Cell].Visited = false
	self.Cells[Cell].Direction = "O"
	table.insert(self.NonVisitedCells, Cell)
	ChangeCellFloorColor(self, Cell, Color3.new(1, 0, 0)) -- Visual feedback
	self.MazeFolder:FindFirstChild(Cell).Middle.Transparency = 0
end

local function EraseLoop(self : Maze, Cell : string, Walk : {string}) : {string?} -- For Wilson algorithm, it erases any loops.
	local Index = table.find(Walk, Cell)
	if not Index then return Walk end -- if for some reason, they cell which is supposed to be in the walk is not there then return walk without modifications.
	if #Walk == 1 then return Walk end -- If the cell is the only one in walk for some reason then just return the walk.

	for i = #Walk, #Walk - Index, -1 do -- This loop took a lot of testing, but it goes from the bottom of the table to right before the index, to delete all items after the index.
		if i < 2 then break end -- this is useless since I already check earlier on, hmmmm.
		SetCellToNotVisited(self, Walk[i])
		Walk[i] = nil
	end
	-- Practically if during the walk u find another cell that is already inside the walk then a loop has occured so just delete all cells after that cell to erase it.
	return Walk
end

local function GetDirectionBetweenCells(self : Maze, Cell1string : string, Cell2string : string) -- Gets Like what direction a cell is relative to the other cell.
	local Cell1 = CoordToTable(Cell1string)
	local Cell2 = CoordToTable(Cell2string)

	if tonumber(Cell2.x) > tonumber(Cell1.x) then return "E" end -- So if Cell2 has a greater x, it means that it is East of Cell1
	if tonumber(Cell2.x) < tonumber(Cell1.x) then return "W" end 
	if tonumber(Cell2.z) < tonumber(Cell1.z) then return "N" end -- So if Cell2 has a lesser z, it means that it is North of Cell1
	if tonumber(Cell2.z) > tonumber(Cell1.z) then return "S" end
end

function MazeGenerator.Create(OriginPosition : Vector3, GridSize : number) : Maze -- Init Function of the Maze, that creates the Maze object in OOP terms.
	local Maze : Maze = {OriginPosition = OriginPosition, GridSize = GridSize}

	local MazeFolder = game:GetService("Workspace").Maze -- Would add the ability to have more than one maze at a time.

	local OriginX = OriginPosition.X
	local OriginZ = OriginPosition.Z

	Cell.Floor.Color = FloorColor
	ChangeWallColor(Cell, WallColor)

	for x = 0, GridSize do -- Simple Grid Loop, for every z coord on the x axis it Clones the Prefab Maze Cell Model, then offset it according to the coords, names it the coords and parents to the MazeFolder.
		for z = 0, GridSize	do
			local NewCell : Model = Cell:Clone()
			local NewCFrame : CFrame = CFrame.new(OriginX + (CellSize * x), 5, OriginZ + (CellSize * z))
			NewCell:PivotTo(NewCFrame)
			NewCell.Name = x..","..z
			NewCell.Parent = MazeFolder
		end
	end

	Maze.MazeFolder = MazeFolder

	return setmetatable(Maze, MazeGenerator) -- OOP things
end

function MazeGenerator.Reset(self : Maze) -- Added this so that you can actually test the maze for the application, so when you click the generate button it resets the maze for the next generation.
	-- Have to clear the folder storing all the cells.
	for _, child in self.MazeFolder:GetChildren() do
		child:Destroy()
	end

	-- set previous to nil then return brand new maze
	local NewMaze = MazeGenerator.Create(self.OriginPosition, self.GridSize)
	self = nil
	return NewMaze 
end

function MazeGenerator.Generate(Algorithm : string, Maze : Maze?) -- This is connected to the generate button on the client
	-- So I just named the algorithm buttons to their respective function names and send their names as an argument.
	local NewMaze
	-- If it is the first Generation it just creates a new maze, else it resets the maze
	if not Maze then
		NewMaze = MazeGenerator.Create(Vector3.zero, 10)
	else
		NewMaze = MazeGenerator.Reset(Maze)
	end

	MazeGenerator[Algorithm](NewMaze)

	return NewMaze
end

function MazeGenerator.GetOriginPosition(self : Maze)
	return self.OriginPosition
end


function MazeGenerator.OriginShift(self : Maze, Iterations : number, UpdateInterval : number?) -- Origin Shift Algorithm, first one I coded.
	local Cells = {} :: {string : Cell} -- Table of all Cells including their direction and whether they are visited, which I would store in self later

	for x = 0, self.GridSize do -- Simple Grid Looping
		for z = 0, self.GridSize do
			if x ~= self.GridSize then
				Cells[x..","..z] = {Direction = "E", Visited = false}
			else
				Cells[x..","..z] = {Direction = "S", Visited = false}
			end
		end
	end
	-- Set all cells that aren't on the final row to E and they ones on the final row south, this makes it a perfect maze at default, as origin maze just keep it perfect in every iteration while changing.

	Cells[self.GridSize..","..self.GridSize].Direction = "O" -- Sets the Final cell as the origin Node.
	self.OriginCell = self.GridSize..","..self.GridSize -- kinda redundant but makes it easier.

	self.Cells = Cells -- store the cells to self.

	local CurrentIteration = 0 -- used in seperating visual updates later on. 
	if not Iterations then Iterations = self.GridSize^3 end
	if not UpdateInterval then UpdateInterval = 1 end

	UpdateMazeWithCells(self, Cells)

	while CurrentIteration < Iterations do		
		local NewDirection = RandomPossibleDirection(self, self.OriginCell)
		Cells[self.OriginCell].Direction = NewDirection -- We set the new direction
		ChangeCellDirection(self, self.OriginCell, NewDirection) -- Redundant, most likely because I hadn't code the visual updater by this time or I am stupid.
		self.MazeFolder[self.OriginCell].Middle.Transparency = 1 -- shows that it has been visited just for visuals

		local NewOriginCell = GetCellFromDirection(self, self.OriginCell, NewDirection)
		Cells[NewOriginCell].Direction = "O" -- It gets the new cell that is in that direction and it becomes the new origin node
		self.OriginCell = NewOriginCell 
		ChangeCellDirection(self, self.OriginCell, "O")

		CurrentIteration += 1
		if CurrentIteration % UpdateInterval == 0 then -- If CurrentIteration can be divided without remainder then it has passed the interval for it to be updated
			UpdateMazeWithCells(self, Cells)
			task.wait()
		end
	end

	UpdateMazeWithCells(self, Cells) -- final update incase update interval isn't a factor of iterations.
end

function MazeGenerator.AldrousBroder(self : Maze, UpdateInterval : number?) -- Another Algorithm, different approach to Originshift
	local Cells = {} :: {string : Cell} 
	local NonVisitedCells = {} :: {string} -- easier way to find cells that aren't visited instead of looping through cells and checking whehter they have visited as false.

	for x = 0, self.GridSize do
		for z = 0, self.GridSize do
			Cells[x..","..z] = {Direction = "O", Visited = false} 
			table.insert(NonVisitedCells, x..","..z)
		end
	end

	self.Cells = Cells
	self.NonVisitedCells = NonVisitedCells

	local CurrentIteration = 0
	UpdateMazeWithCells(self, Cells)
	local CurrentCell = GetRandomNotVisitedCell(self)
	if not UpdateInterval then UpdateInterval = 1 end

	while self.NonVisitedCells[1] do -- until all cells have been visited and given a direction.
		-- Get a random neighbouring Cell by getting a possible direction and then getting the cell from the direction, a later on create a function that does this.
		local RandomDirection = RandomPossibleDirection(self, CurrentCell)
		local NeighbourCell = GetCellFromDirection(self, CurrentCell, RandomDirection)

		-- So the algorithm connects the cells together randomly, so if not visited it would connect them by setting the direction to the opposite thus connecting the cells.

		if not self.Cells[NeighbourCell].Visited then
			self.Cells[NeighbourCell].Direction = OppositeDirection(RandomDirection)
			SetCellToVisited(self, NeighbourCell)
		end

		CurrentCell = NeighbourCell

		CurrentIteration += 1
		if CurrentIteration % 100 == UpdateInterval then
			UpdateMazeWithCells(self, Cells)
			task.wait()
		end
	end

	UpdateMazeWithCells(self, Cells)
end

function MazeGenerator.Wilson(self : Maze, UpdateInterval : number?)
	local Cells = {} :: {string : Cell}
	local NonVisitedCells = {} :: {string}

	for x = 0, self.GridSize do
		for z = 0, self.GridSize do
			Cells[x..","..z] = {Direction = "I", Visited = false}
			table.insert(NonVisitedCells, x..","..z)
		end
	end

	self.Cells = Cells
	self.NonVisitedCells = NonVisitedCells

	local CurrentIteration = 0
	if not UpdateInterval then UpdateInterval = 1 end

	UpdateMazeWithCells(self, Cells)
	local Destination = GetRandomNotVisitedCell(self) -- Wilson is a walk algorithm, so you select a nonvisted cell and randomly work till you find a visited one, so I need to get a visited cell to start.
	SetCellToVisited(self, Destination)

	while self.NonVisitedCells[1] do
		local NeighbourCell
		local CurrentCell = GetRandomNotVisitedCell(self)

		-- randomerror that happened once, doesn't make sense cause if nonvisted is not empty then currencell should not be nil, might have fixed the error and just kept it incase.
		if not CurrentCell then break end

		local walk = { CurrentCell }
		repeat
			CurrentCell = walk[#walk] -- CurrentCell is at the end of the walk to continue the walk.
			local RandomDirection = RandomPossibleDirection(self, CurrentCell, walk)
			local NeighbourCell = GetCellFromDirection(self, CurrentCell, RandomDirection)

			if not table.find(walk, NeighbourCell) then -- if not in walk then we just add it to the walk and change floor color for visuals.
				walk[#walk + 1] = NeighbourCell
				ChangeCellFloorColor(self, NeighbourCell, Color3.new(0, 1, 0))
			elseif table.find(walk, NeighbourCell) then -- if it is already in walk then a loop has occured and we call the eraseloop function to deal with it.
				walk = EraseLoop(self, NeighbourCell, walk)
			end

			CurrentIteration += 1
		until self.Cells[NeighbourCell].Visited -- if it is a visited cell then we have finished the walk.

		for i, Cell in walk do -- We now connect the walk, finalizing it.
			SetCellToVisited(self, Cell)
			ChangeCellFloorColor(self, Cell, Color3.new(0, 0, 1))
			if not walk[i+1] then continue end -- the final cell doesn't have another cell to connect with.

			self.Cells[Cell].Direction = GetDirectionBetweenCells(self, Cell, walk[i+1]) -- we set the direction to the one that would face them together thus connecting them.
			self.Cells[walk[i+1]].Direction = GetDirectionBetweenCells(self, walk[i+1], Cell)
		end

		if CurrentIteration % UpdateInterval == 0 then
			UpdateMazeWithCells(self, self.Cells)
			task.wait()
		end
	end

	for Coord, Info in self.Cells do -- just clears the previous colors to visually show it has finished.
		self.MazeFolder:FindFirstChild(Coord).Middle.Transparency = 0
		ChangeCellFloorColor(self, Coord, Color3.new(0, 0, 1))
	end

end

function MazeGenerator.BinaryTree(self : Maze) -- very simple algorithm
	local Cells = {} :: {string : Cell}
	local RandomDirection = {"S", "W"} -- Algorithm states to set to either South or West

	for x = 0, self.GridSize do
		for z = 0, self.GridSize do
			local Dir = RandomDirection[math.random(1, 2)] -- gets a random number between 1 and 2 puts it as index to get either S or W.
			if x == 0 then Dir = "S" end -- It can't open West if x = 0 as it is at the max west.
			if z == self.GridSize then Dir = "W" end -- It can't open South if z = gridsize as it at the bottom
			if x == 0 and z == self.GridSize then Dir = "I" end -- can't open either ways so we just ignore it.
			Cells[x..","..z] = {Direction = Dir, Visited = true}
		end
	end

	self.Cells = Cells

	UpdateMazeWithCells(self, Cells) -- update it
end

function MazeGenerator.Prism(self : Maze) -- Decided this one cause it looks caller and needs a different approach compared to others
	local Cells = {} :: {string : Cell}
	local NonVisitedCells = {} :: {string}
	local VisitedCells = {} :: {string} -- Visited Cells required this time instead of using not table.find(NonVisitedCells, Cell), also used as a queue before the are actually finalized.
	
	for x = 0, self.GridSize do
		for z = 0, self.GridSize do
			Cells[x..","..z] = {Direction = "I", Visited = false}
			table.insert(NonVisitedCells, x..","..z)
		end
	end

	self.Cells = Cells
	self.NonVisitedCells = NonVisitedCells

	local CurrentIteration = 0

	UpdateMazeWithCells(self, Cells)

	local CurrentCell = GetRandomNotVisitedCell(self)
	table.insert(VisitedCells, CurrentCell)
	self.MazeFolder:FindFirstChild(CurrentCell).Middle.Transparency = 1 -- Visually show it has been visited

	local FinishedCell = 0
	-- 2 fail safes, had a counter so once all cells got a direction it stops or either no more visitedcells which are more of a queue in this func.
	while #NonVisitedCells > 1 or FinishedCell >= self.GridSize ^ 2 do
		if #VisitedCells < 1 then break end
		local RandomVisitedCell = VisitedCells[math.random(1, #VisitedCells)]
		local RandomNotVisitedDir = RandomPossibleNotVisitedDirection(self, RandomVisitedCell) -- gets a random direction that hasn't been visited.

		-- If all the cell neighbours are visited then we finalize the cell, that's why the algorithm expands from the middle.
		if not RandomNotVisitedDir then 
			-- Finalizing the cell
			self.Cells[RandomVisitedCell].Visited = true

			ChangeCellFloorColor(self, RandomVisitedCell, Color3.new(0, 0, 1))
			self.MazeFolder:FindFirstChild(RandomVisitedCell).Middle.Transparency = 0

			table.remove(VisitedCells, table.find(VisitedCells, RandomVisitedCell))
			FinishedCell += 1 
			continue
		end

		-- if it does have one we open the wall between them.
		self.Cells[RandomVisitedCell].Direction = RandomNotVisitedDir

		-- Get the neighbour, visually show it is visited then insery the neighbour in visited/queue and remove from nonvisited
		local NeighbourCell = GetCellFromDirection(self, RandomVisitedCell, RandomNotVisitedDir)
		self.MazeFolder:FindFirstChild(NeighbourCell).Middle.Transparency = 0
		ChangeCellFloorColor(self, NeighbourCell, Color3.new(0, 1, 0))

		table.insert(VisitedCells, NeighbourCell)
		table.remove(NonVisitedCells, table.find(NonVisitedCells, NeighbourCell))

		UpdateMazeWithCells(self, self.Cells)
		task.wait()
	end
	UpdateMazeWithCells(self, self.Cells)
end

local function CalculateHcost(self : Maze, Start : string, Goal : string) -- Returns the distance between the Cell and the Goal, multiply by 10 to remove decimals
	local Distance = (self.MazeFolder:FindFirstChild(Start):GetPivot().Position - self.MazeFolder:FindFirstChild(Goal):GetPivot().Position).Magnitude
	local HeuristicDistance = Distance * 10
	return HeuristicDistance
end

local function IsTraversable(self : Maze, Cell : string, Destination : string, Direction : string) : boolean -- Checks whether their is a wall blocking two cells
	local CellDir = self.Cells[Cell].Direction
	local CellModel = self.MazeFolder:FindFirstChild(Cell)
	local DestinationDir = self.Cells[Destination].Direction
	local DestinationModel = self.MazeFolder:FindFirstChild(Destination)

	-- so if the direction the cell is pointing to is the same as the direction of the next cell then it is traversable, Cell pointing north can transverse the north Cell.
	if CellDir == AbbreviateDir(Direction) then return true end

	-- if the opposite of the cell that it wants to traverse to is equals to the direction it wants to traverse to, it is traversable.
	if OppositeDirection(DestinationDir) == AbbreviateDir(Direction) then return true end

	--final check if the wall is transparent between both a.k.a their is no wall, then it is traversable, instead of using only this thought it would be less intensive to compare strings first, i could be wrong.
	if CellModel[Direction].Transparency == 1 and DestinationModel[UnAbbreviateDir(OppositeDirection(AbbreviateDir(Direction)))].Transparency == 1 then return true end 

	return
end

local function GetPath(self : Maze, CellInfo : {[string] : AStarCellInfo}, Cell : string) 
	local Distance = 80 -- when I add customizable CellSize, it would be CellSize * 10
	local Current : AStarCellInfo = CellInfo[Cell]
	local Path = {}
	local TotalDistance = 0
	while Current.Origin do -- it retraces it path as per the A* algorithm until it is back at the first node which doesn't have an origin.
		if table.find(Path, Current.Origin) then break end -- if we somehow loop then break end
		TotalDistance += Distance -- adds distance to calculate distance cost since it can't move diagonal all the posisble distances are exactly the same.
		table.insert(Path, Current.Origin)
		Current = CellInfo[Current.Origin]
	end

	return {Path = Path, Distance = TotalDistance} -- returns the path and total distance for comparison
end

local function CalculateGcost(self : Maze, CellInfo : {[string] : AStarCellInfo}, Cell : string) -- Gets total distance from the first cell to the cell.
	return GetPath(self, CellInfo, Cell).Distance
end

local function CalculateFcost(self : Maze, CellInfo : {[string] : AStarCellInfo}, Cell : string, Goal : string)
	local Gcost = CalculateGcost(self, CellInfo, Cell)
	local Hcost = CalculateHcost(self, Cell, Goal)
	return Gcost + Hcost
end

local function GetLowestFcost(self : Maze, CellInfo : {[string] : AStarCellInfo})
	local LowestNumber = nil
	local CurrentLowest = {} -- Possibility of more than one lowest fcost sharing the same amount which we filter out later on.

	for Coord, Info in CellInfo do
		if not Info.Fcost then continue end
		if Info.Closed then continue end -- if it has been closed then it isn't a possible path forward.

		if not LowestNumber then -- for the beginning, couldn't preset as it could have been closed.
			LowestNumber = Info.Fcost
			CurrentLowest = { Coord }  
			continue 
		end

		if Info.Fcost < LowestNumber then -- if cell fcost is lower then it is the new lowestnumber
			CurrentLowest = { Coord } -- if it is the new lowest then reset table with only it.
		elseif Info.Fcost == LowestNumber then
			table.insert(CurrentLowest, Coord) -- if it is equal to the lowest add to table.
		end
	end

	-- the lowest Fcost chosen would be the one with the least Hcost, it is also impossible to share hcost so only one possible solution.
	local LowestHcost = CellInfo[CurrentLowest[1]].Hcost -- preset lowest hcost as all cells have an hcost and the closed ones have already been filtered out earlier.
	local LowestCoord = CurrentLowest[1]

	for _, Coord in CurrentLowest do -- loop and set the lowestcoord to the one that is lesser than all hcosts in the loop.
		if CellInfo[Coord].Hcost < LowestHcost then LowestCoord = Coord end
	end

	return LowestCoord
end

local function UpdatePathWithCells(self : Maze, CellInfo : {[string] : AStarCellInfo}) -- Required it owns visualizing to show the path.
	local MazeFolder = self.MazeFolder

	for Coord, Cell in CellInfo do -- set the color depending on its status.
		self.MazeFolder:FindFirstChild(Coord).Middle.Transparency = 0
		if Cell.Start then ChangeCellFloorColor(self, Coord, Color3.new(1,1,1)) continue end
		if Cell.Goal then ChangeCellFloorColor(self, Coord, Color3.new(0)) continue end
		if Cell.Closed then ChangeCellFloorColor(self, Coord, Color3.new(1, 0, 0)) continue end

		ChangeCellFloorColor(self, Coord, Color3.new(0, 1, 0))
	end
end

function MazeGenerator.SolveWithAStar(self : Maze, Start : string, Goal : string, UpdateInterval : number?)
	local Cells = {} :: {string : Cell}
	local CellInfo = {} :: {[string] : AStarCellInfo} -- store all info of the cells required in the algorithm.

	local Iter = 0
	for Cell, Info in self.Cells do
		CellInfo[Cell] = {Closed = false, PathDistance = 565} -- default
	end

	-- initializing the starting cell and final/goal cell.
	CellInfo[Start] = {Fcost = CalculateHcost(self, Start, Goal), Hcost = CalculateHcost(self, Start, Goal), Gcost = CalculateGcost(self, CellInfo, Start), Closed = false, Start = true}
	CellInfo[Goal] = {Closed = false, PathDistance = 565, Goal = true}
	local Current = Start
	if not UpdateInterval then UpdateInterval = 1 end

	while Current ~= Goal do -- until the Goal is reached it runs.
		Current = GetLowestFcost(self, CellInfo)
		CellInfo[Current].Closed = true
		local NeighbourCells = GetNeighbourCoords(self, Current) -- gets all neighbours, the west, north, east and south, returns as [Direction] = coords, ["East"] = "0,1".

		for Direction, Coord in NeighbourCells do -- so sets index to direction and value to Coord.
			if CellInfo[Coord].Start then continue end
			if not IsTraversable(self, Current, Coord, Direction) or CellInfo[Coord].Closed then continue end -- if it can't be traversed or is closed we move on.

			-- if not closed it calculates the values and sets the origin to the current cell else if path is smaller that its old one even though it is closed we recalculate the values.
			if GetPath(self, CellInfo, Coord).Distance < CellInfo[Coord].PathDistance or not CellInfo[Coord].Closed then
				CellInfo[Coord].Fcost = CalculateFcost(self, CellInfo, Coord, Goal)
				CellInfo[Coord].Gcost = CalculateGcost(self, CellInfo, Coord)
				CellInfo[Coord].Hcost = CalculateHcost(self, Coord, Goal)
				CellInfo[Coord].Origin = Current
				if CellInfo[Coord].Closed then CellInfo[Coord].Closed = false end -- We Open it up again.
			end

			Iter += 1
			if Iter % UpdateInterval == 0 then
				UpdatePathWithCells(self, CellInfo)
				task.wait()
			end
		end
	end

	UpdatePathWithCells(self, CellInfo) -- Show the final product

	for _, Coord in GetPath(self, CellInfo, Current).Path do -- Set all to Blue on the path
		ChangeCellFloorColor(self, Coord, Color3.new(0, 0, 1))
	end
	ChangeCellFloorColor(self, Start, Color3.new(1, 1, 1)) -- but set start to white
	ChangeCellFloorColor(self, Goal, Color3.new(0, 0, 0)) -- but set goal to black

end

return MazeGenerator
