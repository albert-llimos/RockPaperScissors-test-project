// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RockPaperScissors {
    
    event GameCreated(
        address indexed playerA,
        address indexed playerB,
        uint256 amount
    );
    
    event JoinedGame(
        address indexed playerA,
        address indexed playerB,
        uint256 amount
    );
    
    event EncryptedMoveSubmitted(
        address indexed player,
        bytes32 encrMove
    );
    
    event MoveCommited(
        address indexed player,
        Moves move
    );
    
    event GameCompleted (
        address indexed playerA,
        address indexed playerB,
        uint256 amount,
        Result result
     );
     
    event EarnedAmount (
        address indexed player,
        uint256 amount,
        uint256 totalAmount
     );        
      
    enum GameState {NotStarted, SubmittingMoves, Commiting, Finalizing}
    
    enum Moves  {None, Rock, Paper, Scissors}
    enum Result {PlayerA, PlayerB, Draw}


    IERC20 public immutable token;

    GameState public gameState;
   
    uint256 betAmount;

    // Encrypted moves
    bytes32 private encrMovePlayerA;
    bytes32 private encrMovePlayerB;  
    
    // Players' addresses
    address playerA;
    address playerB;
    
    // Revealed moves
    Moves private revealedMovePlayerA;
    Moves private revealedMovePlayerB;
    
    // Accomulated Earnings from players
    mapping (address => uint256) public accomulatedEarnings;
    
    // Time limitation to cancel games
    uint public timeGameCreated;
    uint public timeGameLimit;

    modifier stateCheck(GameState _gameState) {
        require(gameState == _gameState, "Game in incorrect state");
        _;
    }
    
    modifier isPlayerinGame() {
        require (msg.sender == playerA || msg.sender == playerB, "Incorrect player");
        _;
    }  
        
    modifier timeLimit () {
        require (block.timestamp > (timeGameCreated + timeGameLimit), "Game still within its time limit");
        _;
    }
    
    
     /**
     * @param _tokenAddress Address of ERC token used to bet
     * @param _timeGameLimit Limit time length that the game can take before it can be cancelled
     * due to inactivity of the player/s
     */

    constructor (address _tokenAddress, uint256 _timeGameLimit) {
        require (_tokenAddress != address(0), "Invalid address for ERC20");
        token = IERC20(_tokenAddress);
        timeGameLimit = _timeGameLimit;
    }

    
     /**
     * Register player for a Game. If a game has not been created it creates one.
     * If a game been created, the new player joins the game.
     * The player creating the game has the possibility to select which address can be player B.
     * 
     * 
     * @param _amount Amount of ERC20 token that is bet
     * @param _playerB Select address of playerB that can join. Setting it to address(0) allows any player to join
     * @param _usePreviousWinnings Use earnings from previous games to pay for the betting amount.
   */
    function register(uint256 _amount, address _playerB, bool _usePreviousWinnings) public stateCheck(GameState.NotStarted) {
        if (playerA == address(0)) {
            _createGame(_amount, _playerB);
        } else {
            require (msg.sender != playerA, "Cannot play with oneself");
            require (playerB == address(0) || playerB == msg.sender , "Incorrect playerB, cannot join the game");
            require (_amount == betAmount , "Wrong amount provided");
            _joinGame();
        }
        
        if (betAmount != 0) {
            _pullAmountFromPlayer (_amount, _usePreviousWinnings);
        }
    }    
    
    function _createGame (uint256 _amount, address _playerB) internal {
            playerA = msg.sender;
            betAmount = _amount;
            playerB = _playerB;
            timeGameCreated = block.timestamp;
            emit GameCreated (playerA, playerB, betAmount);        
    }
    
    function _joinGame () internal {
            playerB = msg.sender;
            gameState = GameState.SubmittingMoves;
            emit JoinedGame (playerA, playerB, betAmount);        
    }
    
    function _pullAmountFromPlayer (uint256 _amount, bool _usePreviousWinnings) internal {
        if (_usePreviousWinnings) {
            require (accomulatedEarnings[msg.sender] >= _amount, "Not enough earnings");
            // Prevent withdrawals. This contract already owns those tokens
            accomulatedEarnings[msg.sender] -= _amount;
        } else {
            // Pull in tokens from sender. Should have been approved by the sender
            bool success = token.transferFrom(msg.sender, address(this), _amount);
            require (success, "Failed to transfer tokens");
        }        
    }
    
     /**
     * Function for the players in the game to submit their move
     * The move has to be encrypted with a value only known to the player.
     * This is a must, otherwise it would be public and everyone could see the chosen move.
     * Encription:
     * encrMove = keccak256(abi.encodePacked( moveChoice , secretValue))
     * 
     * @param encrMove Encrypted move
   */
    
    function submitMove (bytes32 encrMove) public isPlayerinGame() stateCheck(GameState.SubmittingMoves) {
        if (msg.sender == playerA) {
            encrMovePlayerA = encrMove;
        } else {
            encrMovePlayerB = encrMove;
        }
        
        emit EncryptedMoveSubmitted (msg.sender, encrMove);
        
        if (encrMovePlayerA != 0x0 && encrMovePlayerB != 0x0) {
            gameState = GameState.Commiting;
        }
    }
    
        
     /**
     * Once both players have submitted their moves, which are secret, the moves can now be commited.
     * The moves can be revealed by checking that the encripted value is the result of the chosen move 
     * and the secret value.
     * 
     * @param moveChoice Move choince according to Moves struct
     * @param secretValue Secret value used to encode the movement
   */
    
     function commitMove (Moves moveChoice , bytes32 secretValue) public isPlayerinGame() stateCheck(GameState.Commiting) {
        require (moveChoice != Moves.None, "Not a valid move");
        
        if (msg.sender == playerA) {
            require(keccak256(abi.encodePacked( moveChoice , secretValue)) == encrMovePlayerA, "Encrypted move doesn't match chosen move");
            revealedMovePlayerA = moveChoice;
        } else {
            require(keccak256(abi.encodePacked( moveChoice , secretValue)) == encrMovePlayerB,  "Encrypted move doesn't match chosen move");
            revealedMovePlayerB = moveChoice;
        }
        
        emit MoveCommited (msg.sender, moveChoice);
        
        if (revealedMovePlayerB != Moves.None && revealedMovePlayerB != Moves.None) {
          gameState = GameState.Finalizing;
        }
    }   
    
    
     /**
     * Once both movements have been commited the outcome can be evaluated
     * We let anyone run this function since there is no specific reason why
     * only the players should be able to execute it.
     * 
   */
    
    function evaluateResults() public stateCheck(GameState.Finalizing) {
        Result result;
        if (revealedMovePlayerA == revealedMovePlayerB) {
            result = Result.Draw;
        } else if ((revealedMovePlayerA == Moves.Rock     && revealedMovePlayerB == Moves.Scissors) ||
                   (revealedMovePlayerA == Moves.Paper    && revealedMovePlayerB == Moves.Rock)     ||
                   (revealedMovePlayerA == Moves.Scissors && revealedMovePlayerB == Moves.Paper))
                   {
                        result = Result.PlayerA;
        } else {
            result = Result.PlayerB;
        }
        
        emit GameCompleted (playerA, playerB, betAmount, result);
        
        
        if (betAmount != 0) {
             _calculateEarnings(result);
        }
        
        _resetGame();

    }   
    
    function _calculateEarnings (Result _result) internal {
        if (_result == Result.Draw) {
            _refundPlayers();
        } else if (_result == Result.PlayerA) {
            _pay(playerA, 2*betAmount);
        } else {
            _pay(playerB, 2*betAmount);
        }
    }
    
    function _refundPlayers() internal {
            _pay(playerA, betAmount);
            _pay(playerB, betAmount);        
    }
    
    function _pay (address player, uint256 _amount) internal {
        accomulatedEarnings[player] += _amount;
        emit EarnedAmount(player, _amount, accomulatedEarnings[player]);
        
    }
    
    function _resetGame () internal {
        gameState = GameState.NotStarted;
        encrMovePlayerA = 0x0;
        encrMovePlayerB = 0x0;
        playerA = address(0);
        playerB = address(0);
        revealedMovePlayerA = Moves.None;
        revealedMovePlayerB = Moves.None;
       
    }
    
    
     /**
     * Using withdrawal mechanism instead of transfering the tokens after each game to 
     * allow players to bet their previous earnings
     * 
     * @param _amount Amount to withdraw
   */
    function withdraw (uint256 _amount) public {
        require (accomulatedEarnings[msg.sender] >= _amount , "Amount trying to withdraw is too high");
        require (_amount > 0, "Amount cannot be equal to zero");
        accomulatedEarnings[msg.sender] -= _amount;
        token.transfer(msg.sender, _amount);
    }
    
     /**
     * Allowing the cancellation of a registration of player A for a game after a time delay.
     * Allowed to run by anyone so player A can't register an unknown address as player B and
     * this way block the usage of this contract. Also, in case of having inputted the wrong
     * playerB address by mistake
     * 
   */
    function cancelRegister () public timeLimit stateCheck(GameState.NotStarted) {
        require (playerA != address (0), "No players registered");
        _pay(playerA, betAmount);
        _resetGame();
    }

     /**
     * Allowing the cancellation of an ongoing game in case of unresponsive players
     * after a time delay.
     * 
   */
    function cancelGameTimeLimit () public timeLimit {
        require (gameState == GameState.SubmittingMoves || gameState == GameState.Commiting, "Not an ongoing game");
        _refundPlayers(); 
        _resetGame();
    }
    
}
